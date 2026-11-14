// 无控制台窗口启动器：提权后启动 Windows Terminal 中的控制台程序。
using System;
using System.Diagnostics;
using System.IO;

internal static class Launcher
{
    [STAThread]
    private static void Main()
    {
        string worker = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "RecoveryConsole.Worker.exe");
        if (!File.Exists(worker)) {
            Process.Start(new ProcessStartInfo("cmd.exe", "/k echo RecoveryConsole.Worker.exe is missing. Keep the project folder intact.") { UseShellExecute = true });
            return;
        }
        try {
            Process.Start(new ProcessStartInfo("wt.exe", "-w new new-tab \"" + worker + "\"") { UseShellExecute = true });
        } catch (System.ComponentModel.Win32Exception) {
            try { Process.Start(new ProcessStartInfo(worker) { UseShellExecute = true }); }
            catch (Exception) { Process.Start(new ProcessStartInfo("cmd.exe", "/k echo Unable to start the recovery console.") { UseShellExecute = true }); }
        }
    }
}
