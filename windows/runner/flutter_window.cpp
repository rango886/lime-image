#include "flutter_window.h"

#include <imm.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

void ApplyIme(HWND hwnd, bool enabled) {
  if (!hwnd) {
    return;
  }
  if (enabled) {
    ::ImmAssociateContextEx(hwnd, nullptr, IACE_DEFAULT);
  } else {
    // Detaching the input context stops the IME candidate window from
    // swallowing plain key presses.
    ::ImmAssociateContextEx(hwnd, nullptr, 0);
  }
}

BOOL CALLBACK ApplyImeToChild(HWND child, LPARAM param) {
  ApplyIme(child, param != 0);
  return TRUE;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "limeimage/platform",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setImeEnabled") {
          bool enabled = true;
          if (const auto* value = std::get_if<bool>(call.arguments())) {
            enabled = *value;
          }
          SetImeEnabled(enabled);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  // Disable the IME by default: single-key shortcuts win over CJK input.
  SetImeEnabled(false);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetImeEnabled(bool enabled) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  ApplyIme(hwnd, enabled);
  ::EnumChildWindows(hwnd, ApplyImeToChild, enabled ? 1 : 0);
}
