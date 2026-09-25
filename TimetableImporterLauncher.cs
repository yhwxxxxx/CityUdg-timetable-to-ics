using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

namespace TimetableImporterLauncher
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            try
            {
                string script = ReadEmbeddedScript();
                string appDataDir = Path.Combine(
                    Path.GetTempPath(),
                    "TimetableImporter");

                Directory.CreateDirectory(appDataDir);
                string scriptPath = Path.Combine(appDataDir, "timetable_importer.ps1");
                File.WriteAllText(scriptPath, script, new UTF8Encoding(true));

                string powershellPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe");

                if (!File.Exists(powershellPath))
                {
                    powershellPath = "powershell.exe";
                }

                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = powershellPath;
                startInfo.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File " + Quote(scriptPath);
                startInfo.WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory;
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = true;

                Process.Start(startInfo);
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

        private static string ReadEmbeddedScript()
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            using (Stream stream = assembly.GetManifestResourceStream("EmbeddedTimetableImporter"))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("没有找到内置程序文件。");
                }

                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
                {
                    return reader.ReadToEnd();
                }
            }
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }
    }
}
