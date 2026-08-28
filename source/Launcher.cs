using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class Launcher
{
    private static string Quote(string value)
    {
        if (value.Length > 0 && value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
            return value;

        var result = new StringBuilder("\"");
        var backslashes = 0;
        foreach (var ch in value)
        {
            if (ch == '\\')
            {
                backslashes++;
                continue;
            }

            if (ch == '"')
            {
                result.Append('\\', backslashes * 2 + 1);
                result.Append('"');
                backslashes = 0;
                continue;
            }

            result.Append('\\', backslashes);
            backslashes = 0;
            result.Append(ch);
        }

        result.Append('\\', backslashes * 2);
        result.Append('"');
        return result.ToString();
    }

    public static int Main(string[] args)
    {
        try
        {
            var script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "plugin.ps1");
            if (!File.Exists(script))
                return 2;

            var powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");

            var command = new StringBuilder();
            command.Append("-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ");
            command.Append(Quote(script));
            foreach (var arg in args)
            {
                command.Append(' ');
                command.Append(Quote(arg));
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = command.ToString(),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory
            };

            using (var child = Process.Start(startInfo))
            {
                if (child == null)
                    return 3;
                child.WaitForExit();
                return child.ExitCode;
            }
        }
        catch
        {
            return 1;
        }
    }
}
