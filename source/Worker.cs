// Invokes the installer in the current terminal; launcher supplies elevation.
using System;
using System.Diagnostics;
using System.IO;
internal static class Worker {
    static void Log(string text) {
        try { File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launch.log"), DateTime.Now.ToString("s") + " " + text + Environment.NewLine); }
        catch { }
    }
    static int Main() {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        int result = 1;
        try {
            string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "installer.ps1");
            Log("Starting installer.");
            if (!File.Exists(script)) throw new FileNotFoundException("installer.ps1 is missing. Keep the project folder intact.", script);
            var info = new ProcessStartInfo("powershell.exe", "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"");
            info.UseShellExecute = false;
            using (var process = Process.Start(info)) {
                if (process == null) throw new InvalidOperationException("Unable to start PowerShell.");
                process.WaitForExit(); result = process.ExitCode;
                Log("PowerShell exited with code " + result);
                
            }
        } catch (Exception e) {
            Log(e.ToString());
            Console.WriteLine(e is FileNotFoundException ? "Error: 0xE0010007" : "Error: 0xE0010010");
        }
        if (result == 0) {
            Console.WriteLine("Finished. This window will close in 5 seconds.");
            System.Threading.Thread.Sleep(5000);
        } else {
            Console.WriteLine("Stopped. Press Enter to close.");
            try { Console.ReadLine(); } catch { }
        }
        return result;
    }
}
