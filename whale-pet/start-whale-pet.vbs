' DeepSeek Harness 鲸鱼娘桌宠 —— 静默启动（不闪黑框）
' 双击本文件即可；也可由开机自启的快捷方式调用。
Option Explicit
Dim sh, fso, here, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\WhalePet.ps1"""
sh.Run cmd, 0, False
