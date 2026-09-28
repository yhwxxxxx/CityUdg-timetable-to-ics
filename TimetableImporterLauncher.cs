using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("课表导入程序")]
[assembly: AssemblyDescription("将课表文字或图片转换为 iCalendar (.ics) 文件")]
[assembly: AssemblyCompany("CityUdg Timetable to ICS")]
[assembly: AssemblyProduct("课表导入程序")]
[assembly: AssemblyCopyright("Copyright © 2026")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

namespace TimetableImporterLauncher
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            try
            {
                string applicationDirectory = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(applicationDirectory, "timetable_importer.ps1");

                if (!File.Exists(scriptPath))
                {
                    throw new FileNotFoundException(
                        "程序文件不完整：找不到 timetable_importer.ps1。" + Environment.NewLine +
                        "请解压整个发布包，不要只复制 exe 文件。",
                        scriptPath);
                }

                Directory.SetCurrentDirectory(applicationDirectory);
                string script = File.ReadAllText(scriptPath, Encoding.UTF8);
                RunScriptInCurrentProcess(script);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "启动课表导入程序失败：" + Environment.NewLine + ex.Message,
                    "课表导入程序",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        private static void RunScriptInCurrentProcess(string script)
        {
            InitialSessionState sessionState = InitialSessionState.CreateDefault();

            using (Runspace runspace = RunspaceFactory.CreateRunspace(sessionState))
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();

                using (PowerShell powerShell = PowerShell.Create())
                {
                    powerShell.Runspace = runspace;
                    powerShell.AddScript(script, false);
                    powerShell.Invoke();

                    if (powerShell.HadErrors)
                    {
                        string details = string.Join(
                            Environment.NewLine,
                            powerShell.Streams.Error.Select(error => error.ToString()).ToArray());
                        throw new InvalidOperationException(details);
                    }
                }
            }
        }
    }
}
