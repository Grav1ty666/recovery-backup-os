using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
internal static class Launcher {
 [STAThread] static int Main() {
  string root=AppDomain.CurrentDomain.BaseDirectory;
  string worker=Path.Combine(root,"RecoveryConsole.Worker.exe");
  if(!File.Exists(worker)){MessageBox.Show("The recovery program is missing. Please reinstall.","Recovery & Backup OS",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
  try {
   using(Process terminal=Process.Start(new ProcessStartInfo("wt.exe","-w new new-tab \""+worker+"\""){UseShellExecute=true,WorkingDirectory=root})) {
    if(terminal==null)throw new InvalidOperationException();
    if(!terminal.WaitForExit(1500)||terminal.ExitCode==0)return 0;
   }
  } catch(Exception) { }
  try { Process.Start(new ProcessStartInfo(worker){UseShellExecute=true,WorkingDirectory=root});return 0; }
  catch(Exception){MessageBox.Show("Unable to start the recovery program.","Recovery & Backup OS",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
 }
}
