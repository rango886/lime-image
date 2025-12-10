using ImageMagick;
using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace lime_image_viewer
{
    public enum ViewMode
    {
        Auto = 1,
        FocusLock = 2,
        CenterLock = 3,
        FitWidth = 4,
        FitHeight = 5
    }

    public partial class MainWindow : Window
    {
        // --- 支付二维码 Base64 ---
        private const string AlipayBase64 = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAAAKGVYSWZJSSoACAAAAAEAMQECAA4AAAAaAAAAAAAAAEJhbmRpVmlldyA3LjIzTNELgwAAIABJREFUeJztfXl0VEXad9W9vXdI000SQkISCMEkbGGJIKJsMgroOyDCoIDgURY9yBIYnQFxARR1UJTBeVmC46uAijooi4oMMyyiCLJD2AMJhoSsnYROp9O3bz3fH8+kvuL2GkA57/fxOxxObnVtt+pWPfWsRQGA3Matg3SrO/D/O25PwC3G7Qm4xbg9AbcYtyfgFuP2BNxi3J6AW4zbE3CLcXsCbjFuT8Atxv+CCbg+Ycn/FhGLLvTPALBw4cLjx483td5XXnmlQ4cORUVFs2bNIoT88Y9/7NWrV7DM27dvX7VqFQC8/vrraWlp58+fnzNnDv/V4XAsX76cUrpu3bqNGzcGqyQ9PX3hwoWUUnzkTSPsdvuKFSsk6T8fHGNs6tSpFRUVWVlZ8+bN49k0TcfHx//1r3/Fpr/66qumDsL48eP/67/+K0wmCAnG2P3339/Uhgkh33//PQDk5eXh41dffRWildzcXMz2888/A8DBgwfFqpKSklRVBQBxaPxxzz33iHWeOnVK/DUhIYExxn9VVTUlJYUQMnjwYLHUgQMHxFJpaWlYKnTTwfDOO++EHl4ACLMCOGRZdjgcYde11+utra3VJFJKXS5XRUUFpbR58+ayLF/Hy4TomM1mkyTJYrFUVFQQQqKjow0GgyYbAFRWVoqPzZs3r6uri4qKIoSoqlpbW6uqal1dXUxMDM/WvHlzsRJJkux2O19kwcAYq66uZoxF0v9IJyAxMbGgoCBstrVr144fP16TCACPP/44ISQmJqakpCTCFiOEqqp79uzJyMjYs2dPXFwcIWTXrl333nuvJltJSQn+ipAk6fz587gICCGyLA8cOPDo0aPdu3cvKysTC4rDTSk9ceJEy5YtQ3cpLy+vS5cuEfY/0gnQdKWp+LVJIqWUUhq6FfFX/FvzRrgn+Kf7t3VDfb0WTZgAxKpVqzQbJSEEAObPn5+QkBC6rMvleuaZZ/ijXq9/99139Xp9nz59Vq1aRQhZt27dqlWrqqqq/MsCwLBhw9q2bVtfXz979myfzzdo0KA//OEPhJD4+HhCSGpqKlbSrl07/+J2u/3NN98khHzzzTf+5JQxNm/evKqqKrfbPWXKFELIuHHj+vbtG/AtAGDbtm3/+Mc//H964okn7r777tCDEKC6EOBEODk5GVMee+wx/0+AUnry5EkA+OijjzBFQ4R5NrGs1Wr1eDzYCtK67OxsTR7SSIR5nsrKSr1eTwiZPn26WJYJCEiEsZJXX32VECJJ0sWLF8XXxFIHDhzADuTm5orjgERYluWSkhLG2Ntvvx1wMD/88EMAOH78OL7CzSTCmjkLm4KglFqtVv90RVG8Xi9/9Pl8+Ih9kmXZZDLxX/FvcVawOZ/PV1dXF6yTHo8H/zAajTqdzmw2u91urMRqtUqS5PF46urqJEkym82YnzHW0NAQdre8xVtQk5Cenq6haYi//OUv8+fP549r16599tlnCSENDQ2EkKysrO+//57/6r8mELm5uf/zP/8TrGk+jq+//vrkyZNLS0vj4+MBICcnp6ysjDHWo0ePoqKiQYMGIW8xYMCA48ePM8bC0pKbi193AvB0GKBV3TXtqqpaX18vvjaWCrGwCCE+n09RFPw7xJDJsmyxWEwmE2/CYrEwxrxer9vt5guxoaHB7XaTa+ebMcZ5t18Jv+4EhIbP51u1apVOp/vxxx8DZti8efPly5ctFot4tDUajZMnT2aM5eXl7d69m1L66KOP2my2YK3U1NSsWLFCUZSnn34aAHr27EkIoZSOGTPG6XRmZmZitlGjRvXu3buysvLzzz8nhOzatUtRlGbNmo0dO/bm7jlaXAcRDlhPQCIcDAsXLgzRpe7du2M2bJpzwhosXbpUbDoYpk2bRvw44WAIzQkjEQaAm0iEm7y+4Gbsj02qJFjmm9ITDSL82G9il5q8Bb366qvPPfecf0ucqxRx/vz50aNHE0IWL148cOBAnv7UU089+OCDvJLNmzcvWLCAELJu3br09HR+BHrvvfeuXr2q1+sDjsvo0aPvvfdeAGjTpg0h5NChQ5MmTSKErFq1qkePHgE7DwC5ubkrV66klG7cuDExMRHTGWOPPfbY+fPnk5OT+SKglAZsGgDGjBnTv39/TTqlNOAghEaTJyAgmxMMXq/30KFDhJCrV6+K6QkJCSLXdvjwYZyM9u3bd+/enae3b98+ROXx8fHIgiHcbje2hbQ0ICilZWVlhw4dkiRJURSeLknS2bNnjxw5Qgjp3r17WE64VatWrVq1CpEnckQ6AW63e/369WGz/fzzzyF+9Xg8eObLyMjIyspSFOXLL78EgMrKSlwoBw4cyM/Pt9lsgwcPJoTs2LGjrKzMaDQOGzaMEHLkyJGzZ8/q9fphw4bJsnz69OmjR48CwJAhQ/yJsNPp/O677yilzZo1Gz16tMlkwv6rqjp69GhK6Y4dOywWS1xc3IABAzRlAWDfvn2FhYUWi+Whhx4S52PTpk0hCD6iqKgo7EBd01gI3FxxdFlZGYpC582bBwAul8toNBJCJk6cyDlhIhDhBx54gPiJox0Oh6Io0EiEORPOWYfdu3eDwAkvXboUAC5fvowHyhdeeAECiaO7du2KTWNPJk6cSH4TcfSvdcjFfuPf4lGdn7KxeZ6fP2rYroC7gT9XrEnXVC5m4HyW5rzv39UQjUaCCBm6MFsQpXTx4sWizihCdO7cWRyOefPmvf3221ardfv27ZIk7dixo1+/fgaD4dtvv9XpdAcOHBgwYAAAzJ49OzExsbi4GAVhTzzxxAsvvBCMCPu3uHPnThTjvPDCC1wUIQIA1qxZs2vXLkrp0qVL7XY7SvwlSVq9erXb7S4uLu7Xrx8hJD8/Xyw4adKkIUOGNHUQ2rZtGz5T2DVyI9AI42JjY30+HzTyAVwYF0wjtnXrVrE2vgVhJcH4AI0yQLMFITTCOI5gfMCvhyafgoqLi10ul396SkqK0WisqakpLS0lhCQmJvoLIVRVPXfunCRJAHDHHXcYjcb8/HydTldeXh5iwSqKcvHiRUKI0+kU02022x133EEI8dd/iaioqDh79mx5eTkhhFLaokULh8NBKUVxiMvlKi4u5v03Go3t27fHw1J1dTV22L/O5s2bi+odt9sdkPDGxMQ4HI4QfSOk6Svg0UcfDbghaDjhXbt2gd8KII076bx58xhjnAhLkoTpAVdAYWEhZsA8fAVo5M8cmhVArwU2zUt98803mAePwvwnZCkCCoIopTk5OWKLouhQzLZkyZKbvwIipC1hd22R3IVWn/oTRriWvIeGprcA4E/k/SsM0TFNDcG6Eckokcj5gPLyclQV4ecZFRX1wQcfyLK8ZcuWDz74ABsDgL59+27YsAEAMjIyxLeaM2dOdnb21atXn3rqKZ/Ph+kGg2H9+vU8GwCkpqYSQtq0afOPf/yDUrp58+aVK1darVYUkH3yySdffPGFy+VCRdjQoUPxsIjIy8t78cUXCSFjx47NyckpLi5GETfST6fTOWnSJD6gjLGnn366oqICtyaO8+fPP//884SQo0ePEkJat269dOlSSik2Lctybm6uzWY7efLkiBEjCCFLly5NSkrSjFWbNm2WLFlCCOnYsWP4kY1w5yksLBRLNW/eHHUXXCwVUCIWmg8IC40wTnMYR40Yx/XxARy4BTVVGHfq1CkA2LNnj1iqU6dOkZPu6xdHX758Wa/Xq6qalJQEALIsA4DL5aqpqSGEtGjRwmQyybLcunVrQgju9ZTS1q1bq6rarFmzEDXX19ejCQkX918HsC1CiMVigcZFJkmSy+UqKioCgLi4OFVVFUUpLS2VJKmsrKyoqKi6uhq/6Orq6qtXrwJAUVERpVSW5aSkJEmSSktLFUXRSFb0ej225XQ6QyjpAiPCidKsAEKILMuyLKN+3Ofz4ZyvWbMG0/EzBADxV/4YULzMcfDgQawER//6VgBjTGyarwBJkmRZ1uv1+fn5Pp8PiTBP79GjB5bimxv25LXXXkO9aUJCgizLnDjjCuBtod7iN1oBqqri/ImGVgCA6fzL1ZhhRWiVhZXcCPCz9U9HMgAAOOIaZhjTxWXHXwdrY4z59y1YW5EgvG3o2rVrCwoKAABJ3MaNG48dO2Y2m2fNmiVJkiRJyFVNmTIlLi6uU6dOmC0xMREaTwsAsH79+oAHag2efPLJxMTEuLg4rOTTTz89f/68Jo/ZbJ49ezalFI1NGWPLly+vqqq6dOkSNvfRRx/t3LnT4XBMnTo1xHu99957NpuNvxeCUopmE0iEY2Ji0I7m7rvvBgBCyMyZM8VN5rPPPqOUJiYmPvnkk2HfLmhXQkDUiOEBGTVidru9oaEBDTTwtZEIi0YiYj0ozgwL5AN4JSGEceLxH9WKnFHA/zMzM8UOaDhhng2Fcfz4j2Yp/Ne0tDRsmrelYT4yMjIIIX369MFff5UtyGAwWK1Wk8mEcna+87jdbr1eL0rViWBggpAkCbUrRqMxoH2KBl6vV/y+dDodb5pblKCBiSzLOp3OaDQCQMDKDQaDWFV9fT1p1LGgWRHq6BljmM1sNuMM4cI1Go1oHYNN6/V65LcDHgp4JeLgEEJ4qVAIuwLQhic/Px+7jpsdfxO+jeIKWLNmjV5A586dxUrComfPnmLxb775xuv1Xrx40WAw6PX6RYsWeb3e0tJSk8mk1+tnzpwZovITJ07orwV2e+7cuV6vt6GhAfVokiThr5pj6MqVK71e76lTp7Dp119/PeBHjSuAV4JTyAfn3XffvdEVwGUmOp0OP3a+0jXfPp9OMZ3TK5HcET9mEhqPiTiakiQhScQXk2UZZQ/4Tel0Ojw+cq6KVy5Wy3VeyLrzbmOdIkeGtkDiK2ua5qJ1CMIDYyX+gwA3Lo72x+DBg9PS0hRFyc3NFc8DH3/8cVxcXG1tLVohILjEasuWLaJxdXZ2du/evfljXl7ejh07KKXIl8bFxY0aNYo0qsB8Ph+SU0VRli1bxhh75plnAOCee+4hjceEmpqa+Pj4kSNH8jqbN2/+7LPPUkr37Nlz5MiRqKioJ554ghAiy/KyZcsIISNGjBC/FbRKj4mJmTp1KqX0ypUry5YtUxQFm+7WrRulVFXVDz74AHczxNChQwcNGsQft2/frjGJDI/wZAIABD7g448/BgCn0xlwd3v88ccDFtcQYQ0nzMXRiGBmKRqNGAcSYY2DBgc3S8FK8MwWTBzNodGIIXw+n6iFJo18AIfGNP8WaMTgukxFNOs6dCXX1wRvhbd13Tx2CICf4C9skRu1jJswYcLs2bP54549e7p06QIAf//737Ozs/Pz8x9++GFK6axZsxYuXFhdXT1w4EAujHO73ffcc4/P56uursZ9f/369ZmZmaJlrvgy06ZNe+yxxzjLs2bNmsWLFxNC3nnnnYSEhDNnzmDTH3zwAeqWRaA7GACgFw0ADB48GCkzPn7++ecZGRl5eXl4zp44ceKxY8dKS0uzsrIIIdOmTeO8MaV0woQJs2bNopTOmDGjpKSkS5cua9euJYQsWrToueee441qlktA3OgEtGjRonPnzvzxyJEj6NHX0NBAKcXTCCHEbrd37ty5vLwcrpUqnzx5Eg1yEampqWJtIqifMYjT6cS2kpOTMzMza2pq8FHcozm8Xq/oaggAp0+fFjOgCtPj8WA2i8XSuXNns9l84sQJnDZRUu1wOLCfly5dOn36dHR0NP7UunVrFApFjvCccF5e3tWrV51OJ5JNp9O5d+/e+vr6nj17qqpqMBjQsjMrK8tisbRo0QKzFRYWyrJcWlrau3dvSqnG2aqkpGTv3r3cFjw+Pj41NRUAAlryKory008/EUKSkpKSkpIURfn5558ppRrxVFRUFDZ96dKlvXv3Go1G0cRIA0ppdna2aCMsNk0pvXjx4t69eysqKnr37g0Aqqr++OOPAJCVlZWammowGPbu3Usazbk5zp07V1FRYTKZsrKyIrXqDU0iGGO/+93viJ9taFhxNB5ROnToICZycbQGEydODNi6xiLmtddeA4DKykpNJQF1wqiQgEYirIEkSShf0SCYOHru3LkkuG0o54TRFa5jx46Rc8JNIMIg+E/5H5w1EI0+sCX/zBpWgGcTjUTEc33Aglx2JrYi5hcrCQbRiEaEplF/3RznvPw7FiHC6xePHj1aU1NTXV2N037mzJnS0lK9Xn/XXXdRSvv06YNWbMuWLRN9MSZOnJiSkmI2m++88078gn788Uer1fr888/zt2poaHjooYe8Xm+rVq3QCnHFihWZmZmnT59G7duECRPS0tJ4nSkpKSkpKVVVVS1btuSUHDcTs9ncqVOnv/3tb4SQvn37fv/991arNTs7GwAuXLjgrzFHWZ54kl69enX79u0PHjwoEnCLxYKPgwYN6tevH2Ns8eLFLpfr7rvvRiuV8ePHFxYW2mw2pNWPPPJI165d8a0jnYEIV4q/PgAxa9YszMAN7REa83TkA7hZCoIr5TlCm6UgKisrNf4dCM4H+PuoRoKAGjGORYsWgcAH8LdGUQQHmqc3CeGJcGFhYV1d3ZUrV5CnT05OFvVZBoMBzznJycnigjWZTODHuAeDw+Fo1aoVpbS4uPjEiRMXLlwQf1W83vwLF9LT22Nter304INDwE9bnpGZQYARSnr3vqu+ru7QkSOMEUJYQkKC3W5XVfXMmTOEkLi4ONEVu66uLoT/s9FoxCWoqioeh1RVpZRWVVWhthUlj1artW3btgBQV1fHtbAAEB8fL7YVEOGPoZMnT96+fTtpFKq8+eabaEiLWLJkCTol5+XliZ9D5KNPCBkxYgR6mPbs2fPgwYOagleuXDl4LO/b486r7gYClBHoMiyHABcQA2sUEj/33hZCgCb0Gv+nob87/N0bbywGQv785z8/++yzJSUlqDqdNGkSmsIjtm3bhltoQKSkpBw7dgyNWUTf648++ujDDz8kjZt+t27ddu/eTQh54oknRCXE22+/nZOTE/rdw0+Axg4FR5aPr0iXxPTrQEBaSghJTGpdm1eTd7YMGAEgDBgQHPf/K50HAKb6GKg+n48R9XhJzfh7h8q6JT6fquk88SP+/n3gQDkdvpf44ppOim8tpkcyFJEyYg6H4+WXXwaAbt26EULcbveLL77IGLPZbCh0jY2NBYD9+/d/8sknhJCpU6empaXxMX3yyScHDBigqqrINlNK0Xn66tWrM2fOpJSOGjVq3LhxPANSZokSAqrFYgSgBGQmKHuYis6/PgDmU2UGTGWqynwMDJLeumTJW4yxioqKnJwcWZbRVKS6unrmzJm8iUuXLomvmZiY+O677xJCPv/88x9++EEzCJIkzZ8/Pyoqavfu3Rs2bCCEzJ07NzY2lnO8Y8aM4cwHnlBuwgTglEZFRU2fPp0nKoryt7/9zev1zpo1S3Q4PXv2LJpsjhw5krtXUEp///vfE0LKy8tbtWrFZahWq7WystJoNK5evRr1gj///LO/FIEQYjQaLRYVgACRVJC40o0yYKqqMkVVFabKjKk+lflApzI1ymod/ewzhMozZsz861//mpCQ8Msvv0iS9Oqrr3KjUn+0bNlyxowZhJATJ074TwAh5KmnnoqPj1dVFSdg3Lhx4sb7wAMPoBYvcoSfALvdnpCQEBcXxxiTJKmysrKhocE/JAohBABMJhO6vtTU1KDNJabb7XaLxUIpRalkXV0dWq8gzGYz6pCxlCzLGBCjvLxcURS9QWc0Ga0WAkCBAAOCa4ABA5WpTAYme1UdMAaq6vP5fKriU1Uq0eKSK4TQ+vp63DQwTkhAw1ZJkioqKoqLi3U6XUxMTOSuqeXl5dHR0TqdDgXvTqezvr5eluXY2NgIKwmvkPn000/534SQadOmYQr4MRCU0pEjR6JQvl+/fqK50oYNG4YPHx4TE4PH2ddee01UhY8ZM2bMmDGkkQh369YNT6Ljxo375z//OXDAgGcXf9S8GWVAAYARAsAqK8qaRbVo8Hp1Ol1trTPaavapPqaqPlVmPlnx+dxud2pqN6+3HruKRDjYa3LVd7du3YKdRAMCbdl79+6Ny2XGjBlr167t2LHjsWPHIqwhIiKsSfEfev/MGjIVmlcMQRWxFquRNrNKABIQHSOq6lVq1Yaa8kt1NdVRdgdTVb1Fb7EYfarPp0g+lfp8kkEPhDDwo8DBEPrX0KXEt2tqPdcpDbVYLMjTMsbEb5nj8uXLlNKWLVtOnToVAA4dOiR+WQE9s/GMOGzYMNHyG2E1UbvPB1RPgDAiFVWUpia3vHD2VFnFJZl47LFx8S2ifIz5FPDqVJ9CvDJYrIaXXpynMrZ169a9e/dGR0cj/d+9ezeeqhHp6enjxo3jowYAL730EqW0devWCxYs4DLE++67z2w2U0o14sKZM2diHCscBDRmaRKucwIMBsOcOXMMBsOSJUv++Mc/BtyOAMDhcKB3zfDhw8Vwb8HWwaRJkwJ+RM0NRDVLlBJGVSCStU3Lol8uxdoMJZKnuZlYaQN4nNaoKFVWvZLaQBQJlGYmw9y5cwiVKioqUArywgsvUEpfe+01cQLatm0r+v+gKIJSumrVKhQRYlcHDhx43333+fd5ypQpGRkZP/zwAwofrwNNngD/0Qm46KBRix15nVza5S+AMzF3c1JHqQySJFH5F+flpGjJydTszDZer6qndc2Y3szAq3plpQG8DcTrlVkCDp5Yub9gDhrFf1ysJvYhQilbsF8j4YqaPAHLly9funRpbW1tamqqoigTJky4cuVKsMxosevfiVmzZj333HOUUhSHrVu3zn8ZUUpramqwbH11aX1NiSTrqSRJRG5poD6fancYduQdiouLj7G1YGqNp9LZ0OD1NiiKt6HBq3jrrzF+vnLlCipzJk2axDtMKeXmKgMHDszLy0MZHwDMmjULRdD+oJQ+/vjjWMnw4cMvXLjAJYOI06dPY1vz589HqWIINHkCcFs0GAzl5eVer1dV1bAx1PxhNpvFUh6PBx2bguHEyfNFBRdkSSdRKksUCAGQVcauXHZeuFCS0rq1wphXVRWfz6swLwOvz9cpvaM47aqqYhMA4N9hSqnT6RSlubW1tQGP2gjGGFZSXV3tH4/H5/NhWwF1cxpcJw3Q6XQPPfSQqqrcB+Ff//qXeMTu06dPTExMbW3tjh07CCEBxxeNkwGAH9r69+9vs9lqamp27twp5ty+e9/un37yNNTr9DpXdZ2i+hhVzQajyWS66nJJlFBZNpktwKgkyXq9TvH5Oqe32+SpB4CoqKhhw4Y1NDR89913AHDu3DmkRoMGDbJaraWlpahuw+G22+3ooHn06NGCgoKoqKiAW3+HDh3wjwEDBqSnpzudTpQF9ejRQ1RJ/qZekhpxNNqI+/uIIbijtsa25cCBA+AXN3TgwIGjxo4ztWihbx6ts0UZmtsMzW16m1W2R+mbR+lsVp3dKjU3y3azzm7R2c0Gh1nvMC94daHBaCDhvCS//fZbsa0ePXqwQI7aocF55psvjvafrWA/aTZ6f4mVmB6MuEEQ0k2JbDLbFI9b9dT7wEcJYaCCRBjWQShhjAHBilVglFJgQIAQGkZEGPCNIJCoMeCbhhiQCBHpBBQXF4vhTjSglKJUffjw4a+//johZO7cuRMnTkxOTj59+jTvZU1NDdqhrFix4rPPPjOZTAcOHNDpdBs2bMA1gdkyMjJE+zKLxTLrzy8wFXQGM5EkotQzxSsRGZiPUqqqKjAZKJEokf+jXGQArFmzZseOHQOA1atXZ2ZmolWWf8/79OmDbY0YMeLUqVMnT55EPTba6BUVFWlWNmLChAloJTZ06NCLFy9qVPNNQqQT4PP5UKERGlFRUSicKi8vP3PmjCzL6enp/FdullJeXl5eXm61Wtu3b280GuPi4sTRsVqtooSLAevZo9uWf/6TynpJNvzHYFVlKvMy5pNlGYjKGAVGVIkQIsmyTq/TdezYEZv2er0heh4dHY1GJaibq6+vF81V6uvrA5ZF4yJCSEFBQSTDEgKRToDRaAyxAggh+/fvd7lc5eXl//73vwkhLpdLFEscPXq0qqqqtrYWE1NTU9u0aaPX63fv3i3L8tmzZ9F7++DBg7W1tVFRURhY7PDhw+ic3T2ryzsLXvE0NBAqEQL4z2K1OuwOALhy5YriU4x6Q3x8S2BQVlZmMBhW5+be/7vfaTpJKW3btm2bNm0opTji5eXlaAgkniAopZmZmfHx8R6PB5n2tLS05ORknoHH7OnVq5cYdwePRi6Xa9++fZTSdu3ahY8g1FSiEQwBlyo3S9HYhr744osQiAgjNLahfFA0mD59GqpkMjIyKKX33HMPMIBGnTB30NCYpaCXJIeGCHOsXr0aAM6dO4dfDOqEIwQPWfarOGrfFEBTPK01RQQgnSSENv5KQ+e/nh7eCG6mRoxj2bJlP/30k9lsXrFihU6n+/rrrz/++GNCyMyZMzESOTa8YMECje2fiI0bN164cEGW5dWrV0uStGvXLtQJIwoLC8eOHUsIGTp06IQJE3j6559/LkYd3rZt29ix4wghOTNzoqKiNOrvkpISrKRjx47r1q2rqalBsSD+CgDTp0+vqqoKwcYTQuLi4tDo88yZM1hbQKSlpYlaqaYh8pWFuD7LuIA+Yv7RUjQIGC3FH02KlhLMUVuDgKGLg4FbxiFucuji/Px8kUCJmixCSExMDNokFRQUiN5haOvq9XpRQouezTqdTvTeN5lMmkUqRuwjhJSXl4sCXk1Ygbi4OBS5IDl1uVwY5EcTM66kpOTo0aN4bqGUVlRUYKAzFODYbDb0VTp79mx9fb3VakU7FLfbffToUYPBINI2SZIyMzP9rZIwwgIhpLCwsLq6uqioCE0owodKIRHbhnLgkPEVwO0SNERYFC5yESMaZmkcDcUVcODAAfGnBx54QGTZNLM1Y8YMMTMKA0ggllDsCeeH8Y8hQ4ZgDRiyLDs7Gx8DhiyD0ST7AAAO1klEQVTT6XRXrlxhgYAvgrah6CUppodAeL1laB1WQBkvCRLcxH9ENIlwLQtKQkp0NZnFIv6PpPFT44anILh98cz4awhGHYTjg/+7i5xzhOeLJhPhyZMno2G3xkH+lVdeEcWHb7311pkzZxISEl555RVCyH//938fPnwY7w8AgKFDhz788MM8c58+fVauXEkIwbN2QUHBokWLCCGnT5+mlDocDuSuv/rqKx5ZgBCyY8cOjOqzYMEC/yCSvGlETU3N888/L5r9vvHGGw6HQ3PnQVFR0ZQpUwAAj/8VFRWTJ08mhGjMxbZt2/bFF1/wx9TUVJFIXLlyBSsZNWpU+JCHYbcgTRXoIxYWoYlw6GgpTb3ERxM1EcHN0xFhQ5bhFhQaYc3Tr8NHLPwK0Ol0aOiJEg+fz4cENqAjETqQ8lKcz9Lr9WJ+jYE/L2UwGK4jWrmiKB6Phx8BsBLetKIoqqp6vV706saoGrwsY4xfXeBfM2eYNaX4DQecEOKY8B2MRwIL3/uwU4QXHXCJh8FgsFgs8fHx2LYG69ats1gsFovl3//+d11dHXqj80o4vF6vWOrvf/87lgoojg67AkwmEwaox8ft27eLTefk5FgsltTUVJfLVVdXh/sSXwHfffcdNh1wsNLS0rAURnHiK0BRFHwRFDdhlH6LxYIHpI4dO+KvGm/O61wBOJn89dAPPZgHvqqq3EtfNCDQmKEHKxXwMwwLTYRK/ET4o8/nc7vdHo8HLcM0h0jGWIhQx4QQLKVZsjqdDuuhjY7aYiWUUjShiKTz4c3Tt2zZUlxc7HQ6uQO7iCNHjqBGadSoUQ6Ho127dqgF3bdvXzBtjD8qKyuxVAhjbgDIzs4WVawnT54MGC1v8+bNJ0+e5I82m+3pp5+Ojo6Ga01oP/30U7vdXltbG0JtazKZMNK3wWCYMmUKpfSLL74QfSsHDx7cr1+/8vJytFS877770tLSzGYzlurVq1d40hJ6gYh8gDilIidMr42WggWb5CXBQxfj/wG3IP9jdTATT82nt3TpUrEsRqPh2TQ36WmAQTYJIYsWLWKM+Ttq41tzG0Dx/gBK6c0hwvyUrdPpsAw6KaiqKmo52LWRjCRJwkWKiZooSMGGDDNr1hm2ha/kvxVgKQDA4EUkkMMXFieNW5y4C0mS5PP5xL5hV7FO/oL4t6qqGKWFZwYA9PnhiTxbyEEVEHYF4DG0devWVVVVVVVVaPqJl/rZ7Xar1Yq9t9lsdgHbtm2rqqrC3YlS+vHHH1cFh8vlwlHr37+/3W7XhCfHWxQdDsfbb78t9q2+vh6LIyXs3bs3Pmpu8rJarWLH8L4wjq+++kr8tW/fvtiTadOm8cDGhBCLxWK322NiYs6cOSMW79Gjh91uv++++/DxySeftNvtvXr1qqysxFvJIlwBcI0kNxBwxAkhuAMyxjRxbDUyIrPZbLfb0ZkJAPAFwn4NLpdLUy0hRFVVvNpNo/kzmUx4NMAPX5ZlbELz9eGBhD8CgNgTo9EotsilXvX19WK62+3GIEXR0dFi8bq6OqfT6fF4MNHn82HcvkiunEQ0mRO+6667xAV+5syZw4cP88e2bdtiJLFjx44VFRVxC/XQyM/Px4sHNKPfv3//+Pj4+vr6TZs28UYbGhowCCbP1qdPn6ysLIfDgWbbXbp04VdjEEIOHz7srzUEgM2bN7vd7rKyskcffZSno7KMEJKdne1yuVwu15YtW8RSGzduxJDJ6IgxZMiQrl27ck+Inj17er3exMTEyPUcuAUFlRkxv0t8NNDwhGjoCo2cMEeE19lqgOLoS5cucUoIgbwkA94fwBFQIxbsOlsNuEZMA+4leeO40Wgp0BTrz6ZCI2ULXVuwJprwMd4KoClyUBoAAIMHD962bVtycnJAV+HCwkIx1P7x48c3bdpECBk/frzoENGpU6e4uLjq6uqRI0cCwJgxY5566in+6+XLl3GXmDp1qqhH69atm91u93q9aPmUlpaWlJRkMplycnI44woAd911l9VqdTqdhw4dopR+9NFHv/zyC68kPz//0qVLMTExn3zyCaU0JSWlXbt2jLHU1NTCwsLY2FgxPEi7du1QLPjWW29t3bqVK+WvGTJKU1JSUAfw/vvvt2nT5vjx4+h39vzzzzfVRelGtyANQt8jFjZ0cUAHMQ38AzZpEJAF4QGbEME0YhrLuLDQhC6+bsu4UIu0e/fukiTFxMSwCO71i4+PR7fbZs2aAcDVq1fFL6i+vv7+++8HAM1VTJcuXULetUOHDjExMVevXg3oIMch7iqMsT179rjdbpvNhtETMN1ms2Gwz7Nnz+L1A5q9qG/fvhoVGxF0W4jo6OiA19PyDv/www8FBQUa7XdtbS2+9R133KGpMACaOmNNQrAbNDQIfae8Bvz+AA604tKEKuBmKejcGeFNehy4Atq3bx+wFHq8+kNzk14kZim/7k2VvxIgpHe1Jg/cgIFJsLIR1nlzzFJefvnlyH3+EACwaNGiDh06tG7d+ssvv+T98Hg8yEiPHDly7NixHo9n3Lhxqqq2b9/+yy+/JI0WZ6mpqVhq/vz5IpPx+OOPP/LIIxplHMepU6cefvhhABg3btzs2bM1oVydTidG/Nega9euL7/8MiEkJyeHB40AAI2315o1azZs2EApff/998NylMnJySib69SpU+ic/2ksBPw1YhEiEiIs3iMWsHVN08HM0wJaxnMEDNjEoblHTIPru8yzSYiUE5ZluUWLFmGzNTQ0aGQShBAAqKmp8Xq9TqczNjaWMcbl9TExMYqi6HQ69DOx2+16vd7r9VZXVxNC8KY7sZ6ysjJKaYsWLcRjqOZKnbq6OpxpscP80e12o7wBHbLRMpdXgrIE8NthrFZrXFycv0ixRYsW4nIMrfYIjNDzIx5DfREg4DGUMTZ8+HD0f29oaMCcAKCiY7vPl5ubixvL/v37AeDAgQMYtf/bb78VK58zZ44syzExMaJCjVfC0bdvX1mWNbahiYmJiqIoisLjhqJvl6YnPHg3gq8AXjk+8hWAbmWaX3+VFUAahVwQxE4kYDo0Gn3gSzLGcGSh0XCDf8h4SOesrxi1HxoDlGA21hhpmFcuBt0mjaJjEOxHMFHz/fLKNT3hv4rrQGMCoqkk2IgFGysRTRbGrVy5MuCNnQsWLBBFYIji4uKXXnqJNHowu1wutPJ48MEHR4wY4fF4ZsyYoarq+fPnaaMRst1uR9knR1VV1Z/+9CcASElJef/997lCavv27Sh9W7hwYUJCwrlz5958801KqebKgdGjR2dlZXm93smTJ0OjPxoAzJkzx2KxdOzYEQU7r7zySlFRUVRUVG5uLqV0zZo1O3furKqqCsiRcY3bSy+9xGNW+uMPf/hDeMY48i0IU5p0o3ZYH7HQm2ZAYRyH5ia9JpmlcIS+zPMGEVYjprLf1jydUoqnQ0qpy+Vyu91Wq5V/0YQQt9stqsM8Ho/L5aqvr4+KimKMYU4AQPk+AKA9Ns+GpcxmsyzLZrMZHxsaGhRFwbbAj7oaDAakyUajMSoqymg0omuJJElRUVG8LaPRiK3X1dUBgMFgCGiWgG1FPiAe5bddAbGxsR6PR1GUBQsW6HQ6m82GthscmpuwUf/Xpk0bfDHc2THEkE6nmz59Opbq2LGjyBzs3LkT07HDM2bM0Ol0SUlJXq9X8cPXX3+NJg4HDx5UFGX//v34mJubqygKmuYRQl599VWv1+vxeFAnnJOT41+VoihoG8oRdgVUuH5zBw0cKUopHhs0KlYNyUJSrKqqTqcTNxA8tJBG7S6qy/mvXB2NwF9RT+u/C6FOmJfij7yrPBve2cX7GTByo6b/YSmww3rDsaMjAaV0yJAhKSkp/Eqvbt26PfPMM5Ikvf/++5TS9PT0/v37U0pHjBhx5513VlZWfvbZZ4SQ3//+94mJiXq9HkXEd955Z3Z2ttFoRHIaHR29fPlySikyDbytTZs2nThxwmazYQyiPn36+Hw+nU6HlWiA3zjfmmJiYp5++mlKaVlZ2fLly7kz3v79+5cvXw4AHo+HUnrixInly5fzSuLi4h555BH+GBMTg/cfiHH+Ao8M+a22IK4RE81P/G/U1pilbN26lTGGRJhSyokwZuM3avvPNxGEcezae8QCZiaNcUN5N5AIa8ykg1lNa2xDf63QxQhoimwLBENtbC9EDRBOfCZmCJZZNL0SU3hPeAbOPWjyQCA/cvGPYPbo/n2IBE3egt54442AYUTQz0SD1NRUPHcvWbKEh+WhlE6cOFEMAbhhw4Z9+/YBwCeffNKpU6eMjAws9eabbz733HMOh+Pw4cOUUnQCrampwSjCGnYBAQAffvhht27dNKeU2NjYI0eOEEJyc3OXLVsmSdLWrVtFK6u5c+cWFBRkZmauX7+eJyYnJ6OCb9myZbm5uZIk/etf/3I4HGvXrv3LX/5CCNm0aRNGaI50+PzQ5AkI7/gqwGw2o8LP6XRigF2ERhOCRjWk0crTarViKXTiTUpK6tSpk8gz87gyAdG2bVv/SwgMBgMm8lAp7du3Fz+aoqKiEydOaKZNp9N16tSJUsptJtPT0+Pj43klaWlpmujFTUWkE+B2u9esWRN2/8Go+v7AMCj8Ed3KZFkeM2YMP1oAADpVVVZWfv3114QQjHOogcFgGDt2rNiTTZs2iXRYg3379p05c8ZsNo8cOdJ/cygqKkLP8rvvvrtLly7JycmYp1evXl6vl8v4unbtivv7li1bDAbDoUOHeNP79++PjY3FWN6oPktISGiqWUp4ItxUBBRHR4hg5unBEIk4muuE0TbUP1oKEuHQ8LcNRWi8JJuE8EQYbiCc4E1B2KoiaQvCUfgb6cyN1BkmzCIAHD16NMQCD4YuXbpEbp6nabGmpgYJJsJoNIradg1UVT1w4IAYmyorK0tUWp09e7a4uNhgMOAFJwUFBWhf07NnT4vFUlFRgcSpR48eoW85JoQwxn766SfRGxcRHR0d4rqU0GhynMvbuLn4X6mU/38JtyfgFuP2BNxi3J6AW4xbEy/otweeNahohEm18qJbgtunoFuM21vQLcbtCbjFuD0Btxj/B8Sngy4FzzBxAAAAAElFTkSuQmCC";
        private const string WechatBase64 = "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";
        //private const string AlipayBase64 = "";
        //private const string WechatBase64 = "";
        // --- 多语言支持 ---
        private string _currentLang = "zh-CN";
        private Dictionary<string, Dictionary<string, string>> _i18n = new();
        private const string ConfigFileName = "config.txt";
         
        // --- wpf 支持的格式 ---
        private readonly string[] _supportedExtensions =
        {
            ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff", ".webp", ".ico" ,".jfif"
        };

        // ImageMagick 支持格式
        private readonly string[] _magickExtensions =
        {
            ".heic", ".heif", ".avif", ".jxl", ".svg",
            ".psd", ".psb", ".dds", ".tga", ".xcf", ".hdr", ".exr",
            ".dng", ".cr2", ".cr3", ".nef", ".arw", ".orf", ".rw2", ".raf",
            ".sr2", ".srw", ".pef", ".x3f", ".erf", ".mef", ".mos", ".mrw", ".3fr", ".kdc",
            ".jp2", ".j2k", ".jpf", ".jpx", ".jpm", ".mj2",
            ".pbm", ".pgm", ".ppm", ".pnm", ".pam", ".pcx"
        };

        private List<FileInfo> _files = new();
        private int _currentIndex = -1;
        private BitmapSource? _currentSource;
        private readonly SemaphoreSlim _loadGate = new(1, 1);
        private Task? _folderScanTask;
        private string? _currentFolder;
        private bool _startupHandled;
        private bool _isFirstRun = false;

        // --- 交互状态变量 ---
        private ViewMode _currentMode = ViewMode.Auto;
        private bool _isDragging = false;
        private Point _lastMousePos;
        private DispatcherTimer _toastTimer;

        // 懒加载标记
        private bool _qrCodesLoaded = false;

        // 排序状态
        private string _sortField = "Name";
        private bool _sortAsc = true;

        public MainWindow()
        {
            InitializeComponent();
            InitI18n(); // 初始化语言字典

            _toastTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
            _toastTimer.Tick += (s, e) => { ToastBorder.Opacity = 0; _toastTimer.Stop(); };

            this.Loaded += MainWindow_Loaded;
        }

        private void LoadQrCodes()
        {
            if (!string.IsNullOrEmpty(AlipayBase64)) ImgAlipay.Source = Base64ToImage(AlipayBase64);
            if (!string.IsNullOrEmpty(WechatBase64)) ImgWechat.Source = Base64ToImage(WechatBase64);
        }

        private BitmapImage Base64ToImage(string base64String)
        {
            try
            {
                byte[] binaryData = Convert.FromBase64String(base64String);
                BitmapImage bi = new BitmapImage();
                bi.BeginInit();
                bi.StreamSource = new MemoryStream(binaryData);
                bi.EndInit();
                return bi;
            }
            catch
            {
                return null;
            }
        }

        private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            if (_startupHandled) return;
            _startupHandled = true;

            // 1. 加载配置（语言）
            LoadConfig();

            // 2. 如果是第一次运行（或者没有配置文件），显示语言选择弹窗
            if (_isFirstRun)
            {
                SettingsOverlay.Visibility = Visibility.Visible;
            }
            else
            {
                ApplyLanguage();
            }

            var args = Environment.GetCommandLineArgs();

            // 3. 如果有启动参数（文件路径），先尝试加载图片
            if (args.Length > 1 && File.Exists(args[1]))
            {
                await OpenImageAsync(args[1]);
            }

            // 4. 等待渲染
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.Render);

            // 5. 显示窗口
            ShowMainWindow();
        }

        private void ShowMainWindow()
        {
            double screenW = SystemParameters.WorkArea.Width;
            double screenH = SystemParameters.WorkArea.Height;
            double screenL = SystemParameters.WorkArea.Left;
            double screenT = SystemParameters.WorkArea.Top;

            this.Left = screenL + (screenW - this.Width) / 2;
            this.Top = screenT + (screenH - this.Height) / 2;

            this.ShowInTaskbar = true;
            this.Activate();
        }

        #region 多语言系统

        private void LoadConfig()
        {
            try
            {
                string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ConfigFileName);
                if (File.Exists(configPath))
                {
                    string content = File.ReadAllText(configPath).Trim();
                    if (_i18n.ContainsKey(content))
                    {
                        _currentLang = content;
                        _isFirstRun = false;
                    }
                }
                else
                {
                    _isFirstRun = true;
                    _currentLang = "zh-CN";
                }

                // 设置对应的 RadioButton 选中状态
                switch (_currentLang)
                {
                    case "zh-TW": RbZhTW.IsChecked = true; break;
                    case "en-US": RbEnUS.IsChecked = true; break;
                    case "ja-JP": RbJaJP.IsChecked = true; break;
                    case "ko-KR": RbKoKR.IsChecked = true; break;
                    case "fr-FR": RbFrFR.IsChecked = true; break;
                    default: RbZhCN.IsChecked = true; break;
                }
            }
            catch { _isFirstRun = true; }
        }

        private void SaveConfig()
        {
            try
            {
                string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ConfigFileName);
                File.WriteAllText(configPath, _currentLang);
            }
            catch (Exception ex)
            {
                ShowToast(T("MsgSaveFail") + ": " + ex.Message);
            }
        }

        private void InitI18n()
        {
            // 简体中文
            _i18n["zh-CN"] = new Dictionary<string, string>
            {
                { "OpenImg", "打开图片..." }, { "OpenFolder", "打开所在文件夹" },
                { "Prev", "上一张" }, { "Next", "下一张" },
                { "Mode", "缩放模式" }, { "ModeAuto", "自动缩放" }, { "ModeFocus", "焦点锁定" }, { "ModeCenter", "中心锁定" }, { "ModeFitW", "宽度优先" }, { "ModeFitH", "高度优先" },
                { "Sort", "排序方式" }, { "SortNameAsc", "按名称 (正序)" }, { "SortNameDesc", "按名称 (倒序)" },
                { "SortTimeAsc", "按时间 (正序)" }, { "SortTimeDesc", "按时间 (倒序)" },
                { "SortSizeAsc", "按大小 (正序)" }, { "SortSizeDesc", "按大小 (倒序)" },
                { "ZoomIn", "放大窗口" }, { "ZoomOut", "缩小窗口" },
                { "Info", "元数据" }, { "FullScreen", "全屏显示" }, { "Settings", "语言设置" }, { "About", "关于" }, { "Exit", "退出" },
                { "BtnOpen", "打开图片 / 拖入图片" },
                { "MetaTitle", "元数据" }, { "BaseInfo", "基础信息" }, { "XmpEdit", "XMP 元数据编辑" },
                { "Title", "标题 (Title)" }, { "Author", "作者 (Creator)" }, { "Desc", "描述 (Description)" }, { "BtnSave", "保存元数据" },
                { "SettingsTitle", "设置" }, { "LangSelect", "选择语言 (Language)" }, { "BtnConfirm", "确定" },
                { "AboutTitle", "关于" }, { "ProjectIntro", "青柠图片是一款轻量级且高颜值的图片查看器。它集多格式支持与元数据编辑于一身，有五种图片缩放模式，配合人性化的快捷键操作，为您带来高效、流畅的沉浸式看图体验。" },
                { "Donation", "捐赠支持" },
                { "MsgFirst", "已是第一张" }, { "MsgLast", "已是最后一张" },
                { "MsgSaving", "正在保存元数据..." }, { "MsgSaveOk", "保存成功！" },
                { "MsgSaveNoChange", "未检测到更改或保存无效" }, { "MsgSaveFail", "保存失败" },
                { "MsgExifError", "ExifTool 反馈：" }, { "MsgLoading", "加载中..." },
                { "MsgResolution", "分辨率: " }, { "MsgScale", " (缩放: " }, { "MsgNoExifTool", "提示: 未找到 exiftool.exe" },
                { "MsgSorting", "排序: " }, { "MsgAsc", "升序" }, { "MsgDesc", "降序" },
                { "MsgFileName", "文件名: " }, { "MsgSize", "大小: " }, { "MsgDate", "修改: " }
            };

            // 繁体中文
            _i18n["zh-TW"] = new Dictionary<string, string>
            {
                { "OpenImg", "開啟圖片..." }, { "OpenFolder", "開啟所在資料夾" },
                { "Prev", "上一張" }, { "Next", "下一張" },
                { "Mode", "縮放模式" }, { "ModeAuto", "自動縮放" }, { "ModeFocus", "焦點鎖定" }, { "ModeCenter", "中心鎖定" }, { "ModeFitW", "寬度優先" }, { "ModeFitH", "高度優先" },
                { "Sort", "排序方式" }, { "SortNameAsc", "按名稱 (正序)" }, { "SortNameDesc", "按名稱 (倒序)" },
                { "SortTimeAsc", "按時間 (正序)" }, { "SortTimeDesc", "按時間 (倒序)" },
                { "SortSizeAsc", "按大小 (正序)" }, { "SortSizeDesc", "按大小 (倒序)" },
                { "ZoomIn", "放大視窗" }, { "ZoomOut", "縮小視窗" },
                { "Info", "元數據" }, { "FullScreen", "全螢幕顯示" }, { "Settings", "語言設定" }, { "About", "關於" }, { "Exit", "退出" },
                { "BtnOpen", "開啟圖片 / 拖入圖片" },
                { "MetaTitle", "元數據" }, { "BaseInfo", "基礎資訊" }, { "XmpEdit", "XMP 元數據編輯" },
                { "Title", "標題 (Title)" }, { "Author", "作者 (Creator)" }, { "Desc", "描述 (Description)" }, { "BtnSave", "保存元數據" },
                { "SettingsTitle", "設定" }, { "LangSelect", "選擇語言 (Language)" }, { "BtnConfirm", "確定" },
                { "AboutTitle", "關於" }, { "ProjectIntro", "青檸圖片是一款輕量級且高顏值的圖片檢視器。它集多種格式支援與元數據編輯於一身，擁有五種圖片縮放模式，配合人性化的快速鍵操作，為您帶來高效、流暢的沉浸式看圖體驗。" },
                { "Donation", "捐贈支援" },
                { "MsgFirst", "已是第一張" }, { "MsgLast", "已是最後一張" },
                { "MsgSaving", "正在保存元數據..." }, { "MsgSaveOk", "保存成功！" },
                { "MsgSaveNoChange", "未檢測到更改或保存無效" }, { "MsgSaveFail", "保存失敗" },
                { "MsgExifError", "ExifTool 反饋：" }, { "MsgLoading", "載入中..." },
                { "MsgResolution", "解析度: " }, { "MsgScale", " (縮放: " }, { "MsgNoExifTool", "提示: 未找到 exiftool.exe" },
                { "MsgSorting", "排序: " }, { "MsgAsc", "升序" }, { "MsgDesc", "降序" },
                { "MsgFileName", "檔名: " }, { "MsgSize", "大小: " }, { "MsgDate", "修改: " }
            };

            // English
            _i18n["en-US"] = new Dictionary<string, string>
            {
                { "OpenImg", "Open Image..." }, { "OpenFolder", "Open Folder" },
                { "Prev", "Previous" }, { "Next", "Next" },
                { "Mode", "Image scaling mode" }, { "ModeAuto", "Auto Fit" }, { "ModeFocus", "Focus Lock" }, { "ModeCenter", "Center Lock" }, { "ModeFitW", "Fit Width" }, { "ModeFitH", "Fit Height" },
                { "Sort", "Sort By" }, { "SortNameAsc", "Name (Asc)" }, { "SortNameDesc", "Name (Desc)" },
                { "SortTimeAsc", "Date (Oldest)" }, { "SortTimeDesc", "Date (Newest)" },
                { "SortSizeAsc", "Size (Smallest)" }, { "SortSizeDesc", "Size (Largest)" },
                { "ZoomIn", "Zoom In Window" }, { "ZoomOut", "Zoom Out Window" },
                { "Info", "Metadata" }, { "FullScreen", "Toggle Fullscreen" }, { "Settings", "Language" }, { "About", "About" }, { "Exit", "Exit" },
                { "BtnOpen", "Open Image / Drop Here" },
                { "MetaTitle", "Metadata" }, { "BaseInfo", "Basic Info" }, { "XmpEdit", "Edit XMP" },
                { "Title", "Title" }, { "Author", "Creator" }, { "Desc", "Description" }, { "BtnSave", "Save Metadata" },
                { "SettingsTitle", "Settings" }, { "LangSelect", "Language" }, { "BtnConfirm", "OK" },
                { "AboutTitle", "About" }, { "ProjectIntro", "Lime Image is a lightweight and sleek image viewer. It combines multi-format support with metadata editing capabilities. Featuring 5 distinct zoom modes and intuitive shortcut controls, it delivers an efficient, smooth, and immersive viewing experience." },
                { "Donation", "Donation" },
                { "MsgFirst", "Already at first image" }, { "MsgLast", "Already at last image" },
                { "MsgSaving", "Saving metadata..." }, { "MsgSaveOk", "Saved successfully!" },
                { "MsgSaveNoChange", "No changes detected or save invalid" }, { "MsgSaveFail", "Save failed" },
                { "MsgExifError", "ExifTool Output:" }, { "MsgLoading", "Loading..." },
                { "MsgResolution", "Resolution: " }, { "MsgScale", " (Scale: " }, { "MsgNoExifTool", "Tip: exiftool.exe not found" },
                { "MsgSorting", "Sorting: " }, { "MsgAsc", "Asc" }, { "MsgDesc", "Desc" },
                { "MsgFileName", "File: " }, { "MsgSize", "Size: " }, { "MsgDate", "Modified: " }
            };

            // Japanese
            _i18n["ja-JP"] = new Dictionary<string, string>
            {
                { "OpenImg", "画像を開く..." }, { "OpenFolder", "フォルダを開く" },
                { "Prev", "前へ" }, { "Next", "次へ" },
                { "Mode", "画像スケーリングモード" }, { "ModeAuto", "自動調整" }, { "ModeFocus", "フォーカスロック" }, { "ModeCenter", "中央固定" }, { "ModeFitW", "幅に合わせる" }, { "ModeFitH", "高さに合わせる" },
                { "Sort", "並び替え" }, { "SortNameAsc", "名前 (昇順)" }, { "SortNameDesc", "名前 (降順)" },
                { "SortTimeAsc", "日付 (古い順)" }, { "SortTimeDesc", "日付 (新しい順)" },
                { "SortSizeAsc", "サイズ (小さい順)" }, { "SortSizeDesc", "サイズ (大きい順)" },
                { "ZoomIn", "ウィンドウ拡大" }, { "ZoomOut", "ウィンドウ縮小" },
                { "Info", "メタデータ" }, { "FullScreen", "全画面表示" }, { "Settings", "言語設定" }, { "About", "バージョン情報" }, { "Exit", "終了" },
                { "BtnOpen", "画像を開く / ドロップ" },
                { "MetaTitle", "メタデータ" }, { "BaseInfo", "基本情報" }, { "XmpEdit", "XMP 編集" },
                { "Title", "タイトル" }, { "Author", "作成者" }, { "Desc", "説明" }, { "BtnSave", "保存" },
                { "SettingsTitle", "設定" }, { "LangSelect", "言語選択" }, { "BtnConfirm", "OK" },
                { "AboutTitle", "バージョン情報" }, { "ProjectIntro", "Lime Image は、軽量かつスタイリッシュなデザインの画像ビューワーです。多形式対応とメタデータ編集機能を兼ね備え、5つのズームモードと直感的なショートカットキー操作により、効率的でスムーズな没入感のある閲覧体験を提供します。" },
                { "Donation", "寄付" },
                { "MsgFirst", "最初の画像です" }, { "MsgLast", "最後の画像です" },
                { "MsgSaving", "保存中..." }, { "MsgSaveOk", "保存しました！" },
                { "MsgSaveNoChange", "変更がないか、保存が無効です" }, { "MsgSaveFail", "保存に失敗しました" },
                { "MsgExifError", "ExifTool 出力:" }, { "MsgLoading", "読み込み中..." },
                { "MsgResolution", "解像度: " }, { "MsgScale", " (倍率: " }, { "MsgNoExifTool", "ヒント: exiftool.exe が見つかりません" },
                { "MsgSorting", "ソート: " }, { "MsgAsc", "昇順" }, { "MsgDesc", "降順" },
                { "MsgFileName", "ファイル: " }, { "MsgSize", "サイズ: " }, { "MsgDate", "更新日: " }
            };

            // Korean
            _i18n["ko-KR"] = new Dictionary<string, string>
            {
                { "OpenImg", "이미지 열기..." }, { "OpenFolder", "폴더 열기" },
                { "Prev", "이전" }, { "Next", "다음" },
                { "Mode", "이미지 크기 조정 모드" }, { "ModeAuto", "자동 맞춤" }, { "ModeFocus", "초점 잠금" }, { "ModeCenter", "중앙 잠금" }, { "ModeFitW", "너비 맞춤" }, { "ModeFitH", "높이 맞춤" },
                { "Sort", "정렬" }, { "SortNameAsc", "이름 (오름차순)" }, { "SortNameDesc", "이름 (내림차순)" },
                { "SortTimeAsc", "날짜 (오래된순)" }, { "SortTimeDesc", "날짜 (최신순)" },
                { "SortSizeAsc", "크기 (작은순)" }, { "SortSizeDesc", "크기 (큰순)" },
                { "ZoomIn", "창 확대" }, { "ZoomOut", "창 축소" },
                { "Info", "메타데이터" }, { "FullScreen", "전체 화면" }, { "Settings", "언어 설정" }, { "About", "정보" }, { "Exit", "종료" },
                { "BtnOpen", "이미지 열기 / 드래그" },
                { "MetaTitle", "메타데이터" }, { "BaseInfo", "기본 정보" }, { "XmpEdit", "XMP 편집" },
                { "Title", "제목" }, { "Author", "작성자" }, { "Desc", "설명" }, { "BtnSave", "저장" },
                { "SettingsTitle", "설정" }, { "LangSelect", "언어 선택" }, { "BtnConfirm", "확인" },
                { "AboutTitle", "정보" }, { "ProjectIntro", "Lime Image는 가볍고 세련된 디자인을 자랑하는 이미지 뷰어입니다. 다양한 포맷 지원과 메타데이터 편집 기능을 갖추고 있으며, 5가지 줌 모드와 사용자 친화적인 단축키 조작을 통해 효율적이고 부드러운 몰입형 감상 경험을 선사합니다." },
                { "Donation", "기부" },
                { "MsgFirst", "첫 번째 이미지입니다" }, { "MsgLast", "마지막 이미지입니다" },
                { "MsgSaving", "저장 중..." }, { "MsgSaveOk", "저장 성공!" },
                { "MsgSaveNoChange", "변경 사항이 없거나 저장이 유효하지 않습니다" }, { "MsgSaveFail", "저장 실패" },
                { "MsgExifError", "ExifTool 출력:" }, { "MsgLoading", "로딩 중..." },
                { "MsgResolution", "해상도: " }, { "MsgScale", " (비율: " }, { "MsgNoExifTool", "팁: exiftool.exe를 찾을 수 없습니다" },
                { "MsgSorting", "정렬: " }, { "MsgAsc", "오름차순" }, { "MsgDesc", "내림차순" },
                { "MsgFileName", "파일: " }, { "MsgSize", "크기: " }, { "MsgDate", "수정: " }
            };

            // French
            _i18n["fr-FR"] = new Dictionary<string, string>
            {
                { "OpenImg", "Ouvrir une image..." }, { "OpenFolder", "Ouvrir le dossier" },
                { "Prev", "Précédent" }, { "Next", "Suivant" },
                { "Mode", "Mode de mise à l'échelle de l'image" }, { "ModeAuto", "Ajustement auto" }, { "ModeFocus", "Verrouillage focus" }, { "ModeCenter", "Verrouillage centre" }, { "ModeFitW", "Ajuster largeur" }, { "ModeFitH", "Ajuster hauteur" },
                { "Sort", "Trier par" }, { "SortNameAsc", "Nom (Croissant)" }, { "SortNameDesc", "Nom (Décroissant)" },
                { "SortTimeAsc", "Date (Ancien)" }, { "SortTimeDesc", "Date (Récent)" },
                { "SortSizeAsc", "Taille (Petit)" }, { "SortSizeDesc", "Taille (Grand)" },
                { "ZoomIn", "Zoom avant" }, { "ZoomOut", "Zoom arrière" },
                { "Info", "Métadonnées" }, { "FullScreen", "Plein écran" }, { "Settings", "Langue" }, { "About", "À propos" }, { "Exit", "Quitter" },
                { "BtnOpen", "Ouvrir / Déposer ici" },
                { "MetaTitle", "Métadonnées" }, { "BaseInfo", "Infos de base" }, { "XmpEdit", "Éditer XMP" },
                { "Title", "Titre" }, { "Author", "Auteur" }, { "Desc", "Description" }, { "BtnSave", "Enregistrer" },
                { "SettingsTitle", "Paramètres" }, { "LangSelect", "Langue" }, { "BtnConfirm", "OK" },
                { "AboutTitle", "À propos" }, { "ProjectIntro", "Lime Image est une visionneuse d'images légère et élégante. Alliant la prise en charge de multiples formats à l'édition de métadonnées, elle propose 5 modes de zoom. Associée à des raccourcis clavier intuitifs, elle vous offre une expérience de visualisation efficace, fluide et immersive." },
                { "Donation", "Donation" },
                { "MsgFirst", "Déjà à la première image" }, { "MsgLast", "Déjà à la dernière image" },
                { "MsgSaving", "Enregistrement..." }, { "MsgSaveOk", "Enregistré avec succès !" },
                { "MsgSaveNoChange", "Aucun changement détecté" }, { "MsgSaveFail", "Échec de l'enregistrement" },
                { "MsgExifError", "Sortie ExifTool :" }, { "MsgLoading", "Chargement..." },
                { "MsgResolution", "Résolution : " }, { "MsgScale", " (Échelle : " }, { "MsgNoExifTool", "Astuce : exiftool.exe non trouvé" },
                { "MsgSorting", "Tri : " }, { "MsgAsc", "Crois." }, { "MsgDesc", "Décrois." },
                { "MsgFileName", "Fichier : " }, { "MsgSize", "Taille : " }, { "MsgDate", "Modifié : " }
            };
        }

        private string T(string key)
        {
            if (_i18n.ContainsKey(_currentLang) && _i18n[_currentLang].ContainsKey(key))
            {
                return _i18n[_currentLang][key];
            }
            return key;
        }

        private void ApplyLanguage()
        {
            // Menu Items
            Menu_Open.Header = T("OpenImg");
            Menu_Folder.Header = T("OpenFolder");
            Menu_Prev.Header = T("Prev");
            Menu_Next.Header = T("Next");
            Menu_Mode.Header = T("Mode");
            Menu_Auto.Header = T("ModeAuto");
            Menu_Focus.Header = T("ModeFocus");
            Menu_Center.Header = T("ModeCenter");
            Menu_FitW.Header = T("ModeFitW");
            Menu_FitH.Header = T("ModeFitH");
            Menu_Sort.Header = T("Sort");
            Menu_SortNA.Header = T("SortNameAsc");
            Menu_SortND.Header = T("SortNameDesc");
            Menu_SortTA.Header = T("SortTimeAsc");
            Menu_SortTD.Header = T("SortTimeDesc");
            Menu_SortSA.Header = T("SortSizeAsc");
            Menu_SortSD.Header = T("SortSizeDesc");
            Menu_ZIn.Header = T("ZoomIn");
            Menu_ZOut.Header = T("ZoomOut");
            Menu_Info.Header = T("Info");
            Menu_Full.Header = T("FullScreen");
            Menu_Settings.Header = T("Settings");
            Menu_About.Header = T("About");
            Menu_Exit.Header = T("Exit");

            // Main UI
            BtnOpen.Content = T("BtnOpen");

            // Exif Panel - 确保所有标签更新
            TxtMetaTitle.Text = T("MetaTitle");
            TxtBaseInfo.Text = T("BaseInfo");
            TxtXmpEdit.Text = T("XmpEdit");
            TxtL_Title.Text = T("Title");
            TxtL_Author.Text = T("Author");
            TxtL_Desc.Text = T("Desc");
            BtnSaveMeta.Content = T("BtnSave");

            // Settings & About
            TxtSettingsTitle.Text = T("SettingsTitle");
            TxtLangSelect.Text = T("LangSelect");
            BtnSettingsConfirm.Content = T("BtnConfirm");
            TxtAboutTitle.Text = T("AboutTitle");
            TxtProjectIntro.Text = T("ProjectIntro");
            TxtDonation.Text = T("Donation");

            // 如果 Exif 面板已打开，刷新其中的动态文本
            if (ExifOverlay.Visibility == Visibility.Visible)
            {
                UpdateExifUIText();
            }
        }

        // 刷新 Exif 面板中的动态信息文本
        private void UpdateExifUIText()
        {
            string path = GetCurrentPath();
            if (string.IsNullOrEmpty(path)) return;
            var fi = new FileInfo(path);

            ExifName.Text = $"{T("MsgFileName")}{fi.Name}";
            ExifSize.Text = $"{T("MsgSize")}{fi.Length / 1024.0:F2} KB";
            ExifDate.Text = $"{T("MsgDate")}{fi.LastWriteTime:yyyy-MM-dd HH:mm}";

            // 尝试保留当前显示的分辨率数值，只替换前缀
            string currentRes = ExifRes.Text;
            if (!string.IsNullOrEmpty(currentRes))
            {
                // 这里简化，直接显示像素尺寸，因为 ExifTool 异步加载可能还没完
                // 为了不打断 ExifTool 的加载显示，这里只在有数据时更新前缀
            }
        }

        #endregion

        #region 核心加载逻辑

        private async Task OpenImageAsync(string path)
        {
            if (!File.Exists(path)) return;

            string? folder = Path.GetDirectoryName(path);
            bool folderChanged = !string.Equals(_currentFolder, folder, StringComparison.OrdinalIgnoreCase);

            if (folderChanged)
            {
                _currentFolder = folder;
                _folderScanTask = null;
                _files.Clear();
            }

            if (_files.Count == 0)
            {
                _files = new List<FileInfo> { new FileInfo(path) };
                _currentIndex = 0;
                await LoadCurrentAsync();
                _ = EnsureFolderListAsync(path);
                return;
            }

            var existsIndex = _files.FindIndex(f => f.FullName.Equals(path, StringComparison.OrdinalIgnoreCase));
            if (existsIndex < 0)
            {
                _files.Add(new FileInfo(path));
                _currentIndex = _files.Count - 1;
            }
            else
            {
                _currentIndex = existsIndex;
            }

            _ = EnsureFolderListAsync(path);
            await LoadCurrentAsync();
        }

        private Task EnsureFolderListAsync(string path)
        {
            if (_folderScanTask != null) return _folderScanTask;

            _folderScanTask = Task.Run(() =>
            {
                try
                {
                    var files = LoadFolderFiles(path);
                    if (files.Count == 0) return;

                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        _files = files;
                        ApplySorting(path);
                    });
                }
                catch (Exception ex)
                {
                    Application.Current.Dispatcher.Invoke(() => ShowToast($"Load Error: {ex.Message}"));
                }
            });

            return _folderScanTask;
        }

        private List<FileInfo> LoadFolderFiles(string path)
        {
            var folder = Path.GetDirectoryName(path);
            if (string.IsNullOrWhiteSpace(folder)) return new List<FileInfo>();

            var allExts = new HashSet<string>(_supportedExtensions.Concat(_magickExtensions), StringComparer.OrdinalIgnoreCase);

            return Directory.EnumerateFiles(folder)
              .Where(f => allExts.Contains(Path.GetExtension(f)))
              .Select(f => new FileInfo(f))
              .ToList();
        }

        private void ApplySorting(string? keepPath = null)
        {
            if (_files.Count == 0) return;

            IEnumerable<FileInfo> ordered = _sortField switch
            {
                "Name" when _sortAsc => _files.OrderBy(f => f.Name, StringComparer.CurrentCultureIgnoreCase),
                "Name" => _files.OrderByDescending(f => f.Name, StringComparer.CurrentCultureIgnoreCase),
                "Time" when _sortAsc => _files.OrderBy(f => f.LastWriteTimeUtc),
                "Time" => _files.OrderByDescending(f => f.LastWriteTimeUtc),
                "Size" when _sortAsc => _files.OrderBy(f => f.Length),
                _ => _files.OrderByDescending(f => f.Length)
            };

            var currentPath = keepPath ?? GetCurrentPath();
            _files = ordered.ToList();

            if (!string.IsNullOrWhiteSpace(currentPath))
            {
                _currentIndex = _files.FindIndex(f => f.FullName.Equals(currentPath, StringComparison.OrdinalIgnoreCase));
            }
            else
            {
                _currentIndex = _files.Count > 0 ? 0 : -1;
            }

            UpdateTitle();
        }

        private async Task LoadCurrentAsync()
        {
            await _loadGate.WaitAsync();
            try
            {
                if (_currentIndex < 0 || _currentIndex >= _files.Count) return;

                var fileInfo = _files[_currentIndex];
                var path = fileInfo.FullName;

                BitmapSource source = null;
                try
                {
                    if (IsNativeSupported(path))
                    {
                        source = await LoadBitmapNativeAsync(path);
                    }
                    else
                    {
                        source = await LoadBitmapMagickAsync(path);
                    }
                }
                catch (Exception ex)
                {
                    ShowToast($"Load Failed: {ex.Message}");
                    return;
                }

                _currentSource = source;
                MainImage.Source = source;
                BtnOpen.Visibility = Visibility.Collapsed;
                RenderOptions.SetBitmapScalingMode(MainImage, BitmapScalingMode.Fant);

                double dpiX = source.DpiX > 0 ? source.DpiX : 96.0;
                double dpiY = source.DpiY > 0 ? source.DpiY : 96.0;
                double logicalWidth = (source.PixelWidth * 96.0) / dpiX;
                double logicalHeight = (source.PixelHeight * 96.0) / dpiY;

                CalculateAutoFit(logicalWidth, logicalHeight);
                UpdateTitle();
            }
            finally
            {
                _loadGate.Release();
            }
        }

        private static Task<BitmapSource> LoadBitmapNativeAsync(string path)
        {
            return Task.Run(() =>
            {
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
                bitmap.StreamSource = stream;
                bitmap.EndInit();
                bitmap.Freeze();
                return (BitmapSource)bitmap;
            });
        }

        private static Task<BitmapSource> LoadBitmapMagickAsync(string path)
        {
            //  Magick 用于加载复杂格式图片
            return Task.Run(() =>
            {
                using var magickImage = new MagickImage(path);
                var bytes = magickImage.ToByteArray(MagickFormat.Bmp);
                using var ms = new MemoryStream(bytes);
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.StreamSource = ms;
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.EndInit();
                bitmap.Freeze();
                return (BitmapSource)bitmap;
            });
        }

        private bool IsNativeSupported(string path)
        {
            var ext = Path.GetExtension(path);
            return _supportedExtensions.Contains(ext, StringComparer.OrdinalIgnoreCase);
        }

        #endregion

        #region 显示模式逻辑

        private void CalculateAutoFit(double imgW, double imgH)
        {
            double winW = ViewerCanvas.ActualWidth;
            double winH = ViewerCanvas.ActualHeight;
            if (winW == 0) winW = this.Width;
            if (winH == 0) winH = this.Height;

            if (winW == 0 || winH == 0) return;

            Matrix m = ImgMatrixTransform.Matrix;

            if (_currentMode == ViewMode.FocusLock && m.M11 != 1.0 && m.M11 != 0)
            {
                return;
            }

            double newScale = 1.0;
            double scaleFitW = winW / imgW;
            double scaleFitH = winH / imgH;

            switch (_currentMode)
            {
                case ViewMode.Auto:
                case ViewMode.FocusLock:
                case ViewMode.CenterLock:
                    newScale = (scaleFitW < scaleFitH) ? scaleFitW : scaleFitH;
                    break;
                case ViewMode.FitWidth:
                    newScale = scaleFitW;
                    break;
                case ViewMode.FitHeight:
                    newScale = scaleFitH;
                    break;
            }

            if (_currentMode == ViewMode.CenterLock && m.M11 != 1.0 && m.M11 != 0)
            {
                newScale = m.M11;
            }

            double newX = (winW - imgW * newScale) / 2;
            double newY = (winH - imgH * newScale) / 2;

            Matrix newMatrix = new Matrix();
            newMatrix.Scale(newScale, newScale);
            newMatrix.Translate(newX, newY);
            ImgMatrixTransform.Matrix = newMatrix;
        }

        private void SwitchMode(ViewMode mode, string text)
        {
            _currentMode = mode;
            ShowToast($"{T("Mode")}: {text}"); // Update Toast
            if (_currentSource != null)
            {
                double dpiX = _currentSource.DpiX > 0 ? _currentSource.DpiX : 96.0;
                double dpiY = _currentSource.DpiY > 0 ? _currentSource.DpiY : 96.0;
                CalculateAutoFit((_currentSource.PixelWidth * 96.0) / dpiX, (_currentSource.PixelHeight * 96.0) / dpiY);
            }
        }

        private void Window_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            if (_currentSource != null)
            {
                if (_currentMode == ViewMode.Auto || _currentMode == ViewMode.FitWidth || _currentMode == ViewMode.FitHeight)
                {
                    double dpiX = _currentSource.DpiX > 0 ? _currentSource.DpiX : 96.0;
                    double dpiY = _currentSource.DpiY > 0 ? _currentSource.DpiY : 96.0;
                    CalculateAutoFit((_currentSource.PixelWidth * 96.0) / dpiX, (_currentSource.PixelHeight * 96.0) / dpiY);
                }
            }
        }

        #endregion

        #region 交互操作

        private void ViewerCanvas_MouseWheel(object sender, MouseWheelEventArgs e)
        {
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
            {
                double scale = (e.Delta > 0) ? 1.1 : (1.0 / 1.1);
                Point mousePos = e.GetPosition(ViewerCanvas);
                Matrix m = ImgMatrixTransform.Matrix;
                m.ScaleAt(scale, scale, mousePos.X, mousePos.Y);
                ImgMatrixTransform.Matrix = m;
            }
            else
            {
                Navigate(e.Delta > 0 ? -1 : 1);
            }
        }

        private void ViewerCanvas_MouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ChangedButton == MouseButton.Left)
            {
                _isDragging = true;
                _lastMousePos = e.GetPosition(ViewerCanvas);
                ViewerCanvas.CaptureMouse();
                Cursor = Cursors.ScrollAll;
            }
        }

        private void ViewerCanvas_MouseMove(object sender, MouseEventArgs e)
        {
            if (_isDragging)
            {
                Point currentPos = e.GetPosition(ViewerCanvas);
                Vector delta = currentPos - _lastMousePos;
                Matrix m = ImgMatrixTransform.Matrix;
                m.Translate(delta.X, delta.Y);
                ImgMatrixTransform.Matrix = m;
                _lastMousePos = currentPos;
            }
        }

        private void ViewerCanvas_MouseUp(object sender, MouseButtonEventArgs e)
        {
            if (_isDragging)
            {
                _isDragging = false;
                ViewerCanvas.ReleaseMouseCapture();
                Cursor = Cursors.Arrow;
            }
        }

        private async void Navigate(int direction)
        {
            if (_files.Count <= 1) return;

            int next = _currentIndex + direction;
            if (next >= _files.Count) next = 0;
            if (next < 0) next = _files.Count - 1;

            _currentIndex = next;
            await LoadCurrentAsync();
        }

        #endregion

        #region 菜单与快捷键

        private void Menu_Prev_Click(object sender, RoutedEventArgs e) => Navigate(-1);
        private void Menu_Next_Click(object sender, RoutedEventArgs e) => Navigate(1);
        private void Menu_ModeAuto_Click(object sender, RoutedEventArgs e) => SwitchMode(ViewMode.Auto, T("ModeAuto"));
        private void Menu_ModeFocus_Click(object sender, RoutedEventArgs e) => SwitchMode(ViewMode.FocusLock, T("ModeFocus"));
        private void Menu_ModeCenter_Click(object sender, RoutedEventArgs e) => SwitchMode(ViewMode.CenterLock, T("ModeCenter"));
        private void Menu_ModeFitW_Click(object sender, RoutedEventArgs e) => SwitchMode(ViewMode.FitWidth, T("ModeFitW"));
        private void Menu_ModeFitH_Click(object sender, RoutedEventArgs e) => SwitchMode(ViewMode.FitHeight, T("ModeFitH"));

        private void Menu_SortNameAsc_Click(object sender, RoutedEventArgs e) => ApplySort("Name", true);
        private void Menu_SortNameDesc_Click(object sender, RoutedEventArgs e) => ApplySort("Name", false);
        private void Menu_SortTimeAsc_Click(object sender, RoutedEventArgs e) => ApplySort("Time", true);
        private void Menu_SortTimeDesc_Click(object sender, RoutedEventArgs e) => ApplySort("Time", false);
        private void Menu_SortSizeAsc_Click(object sender, RoutedEventArgs e) => ApplySort("Size", true);
        private void Menu_SortSizeDesc_Click(object sender, RoutedEventArgs e) => ApplySort("Size", false);

        private void Menu_WinZoomIn_Click(object sender, RoutedEventArgs e) => ResizeWindow(1.1);
        private void Menu_WinZoomOut_Click(object sender, RoutedEventArgs e) => ResizeWindow(0.9);

        // 新增菜单事件
        private void Menu_Settings_Click(object sender, RoutedEventArgs e) => SettingsOverlay.Visibility = Visibility.Visible;

        // 懒加载“关于”页面中的二维码
        private void Menu_About_Click(object sender, RoutedEventArgs e)
        {
            if (!_qrCodesLoaded)
            {
                LoadQrCodes();
                _qrCodesLoaded = true;
            }
            AboutOverlay.Visibility = Visibility.Visible;
        }

        // 设置/关于页面事件
        private void CloseSettings_Click(object sender, RoutedEventArgs e) => SettingsOverlay.Visibility = Visibility.Collapsed;
        private void CloseAbout_Click(object sender, RoutedEventArgs e) => AboutOverlay.Visibility = Visibility.Collapsed;

        // 语言按钮点击事件
        private void LangRadio_Click(object sender, RoutedEventArgs e)
        {
            if (sender is RadioButton rb && rb.Tag is string langCode)
            {
                _currentLang = langCode;
                ApplyLanguage(); // 立即预览语言变化
            }
        }

        private void BtnSettingsConfirm_Click(object sender, RoutedEventArgs e)
        {
            SaveConfig();
            SettingsOverlay.Visibility = Visibility.Collapsed;
        }

        private void Overlay_MouseDown(object sender, MouseButtonEventArgs e)
        {
            // 点击黑色背景关闭
            if (e.OriginalSource == SettingsOverlay) SettingsOverlay.Visibility = Visibility.Collapsed;
            if (e.OriginalSource == AboutOverlay) AboutOverlay.Visibility = Visibility.Collapsed;
        }

        private void ApplySort(string field, bool asc)
        {
            _sortField = field;
            _sortAsc = asc;
            ApplySorting();
            string sortOrder = asc ? T("MsgAsc") : T("MsgDesc");
            ShowToast($"{T("MsgSorting")}{field} ({sortOrder})");
        }

        private void Menu_OpenFolder_Click(object sender, RoutedEventArgs e)
        {
            string path = GetCurrentPath();
            if (!string.IsNullOrEmpty(path))
            {
                Process.Start("explorer.exe", $"/select,\"{path}\"");
            }
        }

        private void Menu_Info_Click(object sender, RoutedEventArgs e) => ShowExif();
        private void Menu_FullScreen_Click(object sender, RoutedEventArgs e) => ToggleFullScreen();
        private void Menu_Exit_Click(object sender, RoutedEventArgs e) => Application.Current.Shutdown();

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            // 当焦点在输入框中时，忽略大多数应用快捷键，防止打字冲突
            // 只保留 Esc 用于关闭界面
            if (e.OriginalSource is TextBox)
            {
                if (e.Key == Key.Escape)
                {
                    // 允许继续执行下面的 Escape 逻辑来关闭浮层
                }
                else
                {
                    // 其他键（如 N, T, S, 箭头等）在输入框内按预期处理（打字/光标移动），不触发 App 功能
                    return;
                }
            }

            bool shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
            switch (e.Key)
            {
                case Key.Left: Navigate(-1); break;
                case Key.Right: Navigate(1); break;
                case Key.PageUp: Navigate(-1); break;
                case Key.PageDown: Navigate(1); break;
                case Key.Home:
                    if (_files.Count > 0) { _currentIndex = 0; _ = LoadCurrentAsync(); ShowToast(T("MsgFirst")); }
                    break;
                case Key.End:
                    if (_files.Count > 0) { _currentIndex = _files.Count - 1; _ = LoadCurrentAsync(); ShowToast(T("MsgLast")); }
                    break;
                case Key.D1: SwitchMode(ViewMode.Auto, T("ModeAuto")); break;
                case Key.D2: SwitchMode(ViewMode.FocusLock, T("ModeFocus")); break;
                case Key.D3: SwitchMode(ViewMode.CenterLock, T("ModeCenter")); break;
                case Key.D4: SwitchMode(ViewMode.FitWidth, T("ModeFitW")); break;
                case Key.D5: SwitchMode(ViewMode.FitHeight, T("ModeFitH")); break;
                case Key.OemPlus: case Key.Add: ResizeWindow(1.1); break;
                case Key.OemMinus: case Key.Subtract: ResizeWindow(0.9); break;
                case Key.L: Menu_OpenFolder_Click(null, null); break;
                case Key.N: ApplySort("Name", !shift); break;
                case Key.T: ApplySort("Time", !shift); break;
                case Key.S: ApplySort("Size", !shift); break;
                case Key.I: ShowExif(); break;
                case Key.F11: ToggleFullScreen(); break;
                case Key.Escape:
                    if (ExifOverlay.Visibility == Visibility.Visible) ExifOverlay.Visibility = Visibility.Collapsed;
                    else if (SettingsOverlay.Visibility == Visibility.Visible) SettingsOverlay.Visibility = Visibility.Collapsed;
                    else if (AboutOverlay.Visibility == Visibility.Visible) AboutOverlay.Visibility = Visibility.Collapsed;
                    else Application.Current.Shutdown();
                    break;
            }
        }

        #endregion

        #region 辅助功能

        private string GetCurrentPath()
        {
            if (_currentIndex >= 0 && _currentIndex < _files.Count) return _files[_currentIndex].FullName;
            return null;
        }

        private void UpdateTitle()
        {
            string path = GetCurrentPath();
            if (!string.IsNullOrEmpty(path))
            {
                this.Title = $"{Path.GetFileName(path)} - {_currentIndex + 1}/{_files.Count}";
            }
        }

        private void ShowToast(string msg)
        {
            ToastText.Text = msg;
            ToastBorder.Opacity = 1;
            _toastTimer.Stop();
            _toastTimer.Start();
        }

        private void ResizeWindow(double factor)
        {
            // 1. 获取屏幕工作区限制
            // SystemParameters.WorkArea 获取的是主屏幕的工作区（去除任务栏后的区域）
            double screenW = SystemParameters.WorkArea.Width;
            double screenH = SystemParameters.WorkArea.Height;
            double screenL = SystemParameters.WorkArea.Left;
            double screenT = SystemParameters.WorkArea.Top;

            double oldW = this.Width;
            double oldH = this.Height;

            // 2. 计算新尺寸
            double newW = Math.Max(400, oldW * factor);
            double newH = Math.Max(300, oldH * factor);

            // 限制不超过屏幕大小
            if (newW > screenW) newW = screenW;
            if (newH > screenH) newH = screenH;

            // 3. 如果尺寸有变化，则执行调整
            if (Math.Abs(newW - oldW) > 1 || Math.Abs(newH - oldH) > 1)
            {
                // 计算当前中心点，基于中心点缩放
                double centerX = this.Left + oldW / 2;
                double centerY = this.Top + oldH / 2;

                double newLeft = centerX - newW / 2;
                double newTop = centerY - newH / 2;

                // --- 4. 边界修正 (关键逻辑：防止窗口跑出屏幕) ---

                // 修正右边界：如果窗口右边超出了屏幕右侧，往左移
                if (newLeft + newW > screenL + screenW)
                {
                    newLeft = (screenL + screenW) - newW;
                }

                // 修正下边界：如果窗口底部超出了屏幕底部，往上移
                if (newTop + newH > screenT + screenH)
                {
                    newTop = (screenT + screenH) - newH;
                }

                // 修正左边界 (优先级高于右边界)：绝对不能让左边跑出去
                if (newLeft < screenL)
                {
                    newLeft = screenL;
                }

                // 修正上边界 (优先级最高)：绝对不能让标题栏跑出去！
                if (newTop < screenT)
                {
                    newTop = screenT;
                }

                // --- 应用修正后的坐标和尺寸 ---
                this.Left = newLeft;
                this.Top = newTop;
                this.Width = newW;
                this.Height = newH;

                ShowToast(factor > 1 ? T("ZoomIn") : T("ZoomOut"));
            }
        }

        private void ToggleFullScreen()
        {
            if (this.WindowStyle != WindowStyle.None)
            {
                this.WindowStyle = WindowStyle.None;
                this.WindowState = WindowState.Normal;
                this.ResizeMode = ResizeMode.CanResize;
            }
            else
            {
                this.WindowState = (this.WindowState == WindowState.Maximized) ? WindowState.Normal : WindowState.Maximized;
            }
        }

        private async void BtnOpen_Click(object sender, RoutedEventArgs e)
        {
            OpenFileDialog dlg = new OpenFileDialog();
            var allExts = _supportedExtensions.Concat(_magickExtensions)
                                            .Select(ext => $"*{ext}")
                                            .OrderBy(ext => ext)
                                            .ToArray();
            string extString = string.Join(";", allExts);
            dlg.Filter = $"Supported Images|{extString}|All Files|*.*";
            if (dlg.ShowDialog() == true) await OpenImageAsync(dlg.FileName);
        }

        private async void Window_Drop(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files != null && files.Length > 0) await OpenImageAsync(files[0]);
            }
        }

        #region 自定义标题栏逻辑
        private void TitleBar_MouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 2) { WinMax_Click(null, null); return; }
            if (e.ChangedButton == MouseButton.Left) this.DragMove();
        }
        private void WinMin_Click(object sender, RoutedEventArgs e) => this.WindowState = WindowState.Minimized;
        private void WinMax_Click(object sender, RoutedEventArgs e) => this.WindowState = (this.WindowState == WindowState.Normal) ? WindowState.Maximized : WindowState.Normal;
        private void WinClose_Click(object sender, RoutedEventArgs e) => Application.Current.Shutdown();
        #endregion

        #endregion

        #region ExifTool 与信息处理逻辑 (Process 命令行版本)

        private void CloseExif_Click(object sender, RoutedEventArgs e) => ExifOverlay.Visibility = Visibility.Collapsed;
        private void ExifOverlay_MouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.OriginalSource == ExifOverlay) ExifOverlay.Visibility = Visibility.Collapsed;
        }

        private void ShowExif()
        {
            string path = GetCurrentPath();
            if (string.IsNullOrEmpty(path)) return;

            // 基础信息从文件系统读取，速度最快
            var fi = new FileInfo(path);
            ExifName.Text = $"{T("MsgFileName")}{fi.Name}";
            ExifSize.Text = $"{T("MsgSize")}{fi.Length / 1024.0:F2} KB";
            ExifDate.Text = $"{T("MsgDate")}{fi.LastWriteTime:yyyy-MM-dd HH:mm}";
            ExifPath.Text = path;

            // 清空 XMP 文本框
            TxtXmpTitle.Text = "";
            TxtXmpCreator.Text = "";
            TxtXmpDesc.Text = "";
            ExifRes.Text = T("MsgLoading");

            ExifOverlay.Visibility = Visibility.Visible;

            // 异步使用 ExifTool 读取详细信息 (命令行方式)
            Task.Run(async () =>
            {
                string t = "", c = "", d = "";
                string width = "", height = "";
                bool toolFound = true;

                try
                {
                    // 构造参数文件内容 (解决中文路径和空格问题)
                    // 使用 -charset filename=utf8 来支持文件名中的中文
                    // 注意：-s -utf8 这些是 ExifTool 选项，不能直接全塞在一行

                    var argLines = new List<string>
                    {
                        "-s",
                        "-utf8",
                        "-Title",
                        "-XMP:Title",
                        "-Creator",
                        "-XMP:Creator",
                        "-Artist",
                        "-Description",
                        "-XMP:Description",
                        "-Caption-Abstract",
                        "-ImageWidth",
                        "-ImageHeight",
                        path // 路径单独占一行，不需要引号，ArgFile 自动处理
                    };

                    string output = await RunExifToolWithArgFileAsync(argLines);

                    if (string.IsNullOrEmpty(output))
                    {
                        // 空输出
                    }
                    else
                    {
                        using (StringReader reader = new StringReader(output))
                        {
                            string line;
                            while ((line = reader.ReadLine()) != null)
                            {
                                var parts = line.Split(new[] { ':' }, 2);
                                if (parts.Length < 2) continue;

                                string tag = parts[0].Trim();
                                string val = parts[1].Trim();

                                if (tag == "Title") t = val;
                                else if (tag == "Creator" || tag == "Artist") c = val;
                                else if (tag == "Description" || tag == "Caption-Abstract") d = val;
                                else if (tag == "ImageWidth") width = val;
                                else if (tag == "ImageHeight") height = val;
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    Debug.WriteLine("ExifTool Run Error: " + ex.Message);
                    if (ex.Message.Contains("系统找不到") || ex is System.ComponentModel.Win32Exception)
                    {
                        toolFound = false;
                        d = T("MsgNoExifTool");
                    }
                }

                Application.Current.Dispatcher.Invoke(() =>
                {
                    // 更新分辨率显示
                    if (!string.IsNullOrEmpty(width) && !string.IsNullOrEmpty(height))
                    {
                        ExifRes.Text = $"{T("MsgResolution")}{width} x {height}";
                        // 如果有当前缩放比例，附加显示
                        double scale = ImgMatrixTransform.Matrix.M11 * 100;
                        ExifRes.Text += $"{T("MsgScale")}{scale:F0}%)";
                    }
                    else if (_currentSource != null)
                    {
                        // 降级：如果 ExifTool 没读到，用 WPF 渲染时的尺寸
                        ExifRes.Text = $"{T("MsgResolution")}{_currentSource.PixelWidth} x {_currentSource.PixelHeight}";
                    }

                    TxtXmpTitle.Text = t;
                    TxtXmpCreator.Text = c;
                    TxtXmpDesc.Text = d;

                    if (!toolFound) ShowToast(T("MsgNoExifTool"));
                });
            });
        }

        private async void BtnSaveXmp_Click(object sender, RoutedEventArgs e)
        {
            string path = GetCurrentPath();
            if (string.IsNullOrEmpty(path)) return;

            string title = TxtXmpTitle.Text.Trim();
            string creator = TxtXmpCreator.Text.Trim();
            string desc = TxtXmpDesc.Text.Trim();

            ShowToast(T("MsgSaving"));

            await Task.Run(async () =>
            {
                try
                {
                    // 使用 ArgFile 模式构造参数
                    var argLines = new List<string>
                    {
                        "-overwrite_original",
                        "-utf8",
                        "-m" // Ignore minor errors
                    };

                    if (!string.IsNullOrEmpty(title)) argLines.Add($"-XMP:Title={title}");
                    if (!string.IsNullOrEmpty(creator))
                    {
                        argLines.Add($"-XMP:Creator={creator}");
                        argLines.Add($"-IPTC:By-line={creator}");
                    }
                    if (!string.IsNullOrEmpty(desc))
                    {
                        argLines.Add($"-XMP:Description={desc}");
                        argLines.Add($"-IPTC:Caption-Abstract={desc}");
                    }

                    argLines.Add(path); // 目标文件路径放在最后

                    string output = await RunExifToolWithArgFileAsync(argLines);

                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        // 检查 ExifTool 的实际输出结果
                        if (output.Contains("image files updated"))
                        {
                            ShowToast(T("MsgSaveOk"));
                            var fi = new FileInfo(path);
                            ExifDate.Text = $"{T("MsgDate")}{fi.LastWriteTime:yyyy-MM-dd HH:mm}";
                        }
                        else if (output.Contains("0 image files updated"))
                        {
                            // 可能是内容未改变，或者文件被锁定但未报错
                            ShowToast(T("MsgSaveNoChange"));
                            MessageBox.Show($"{T("MsgExifError")}\n{output}", T("MsgSaveNoChange"));
                        }
                        else
                        {
                            // 其他错误
                            ShowToast(T("MsgSaveFail"));
                            MessageBox.Show($"{T("MsgSaveFail")}, {T("MsgExifError")}\n{output}", "Error");
                        }
                    });
                }
                catch (Exception ex)
                {
                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        ShowToast(T("MsgSaveFail"));
                        if (ex.Message.Contains("系统找不到") || ex is System.ComponentModel.Win32Exception)
                        {
                            MessageBox.Show(T("MsgNoExifTool"), "Missing Component");
                        }
                        else
                        {
                            MessageBox.Show($"Error: {ex.Message}", "Error");
                        }
                    });
                }
            });
        }

        // 核心辅助方法：使用参数文件调用 exiftool.exe
        // 这解决了长路径、空格、中文乱码、引号转义等所有问题
        private async Task<string> RunExifToolWithArgFileAsync(List<string> args)
        {
            // 创建临时参数文件
            string tempArgFile = Path.GetTempFileName();
            await File.WriteAllLinesAsync(tempArgFile, args, Encoding.UTF8);

            var tcs = new TaskCompletionSource<string>();

            var psi = new ProcessStartInfo
            {
                FileName = "exiftool.exe",
                Arguments = $"-@ \"{tempArgFile}\"", // 让 ExifTool 读取这个文件
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8
            };

            try
            {
                var process = new Process { StartInfo = psi };
                process.EnableRaisingEvents = true;

                var output = new StringBuilder();

                process.OutputDataReceived += (s, e) => { if (e.Data != null) output.AppendLine(e.Data); };
                process.ErrorDataReceived += (s, e) => { if (e.Data != null) output.AppendLine(e.Data); }; // 捕获错误输出

                process.Exited += (s, e) =>
                {
                    tcs.SetResult(output.ToString());
                    process.Dispose();
                    // 删除临时文件
                    try { File.Delete(tempArgFile); } catch { }
                };

                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                tcs.SetException(ex);
                try { File.Delete(tempArgFile); } catch { }
            }

            return await tcs.Task;
        }

        #endregion
    }
}