"""Send one command to the already selected TD Tcl Console input."""
import argparse
import ctypes
import time

import win32api
import win32clipboard
import win32con
import win32gui

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('command')
parser.add_argument('--hwnd',type=int)
args = parser.parse_args()
ctypes.windll.user32.SetProcessDPIAware()
windows = []
win32gui.EnumWindows(lambda handle, _: windows.append(handle)
                     if 'Anlogic TD' in win32gui.GetWindowText(handle) else None, None)
if args.hwnd is not None:
    windows=[h for h in windows if h==args.hwnd]
if len(windows) != 1:
    raise SystemExit('Expected exactly one TD project window')
handle = windows[0]
win32gui.ShowWindow(handle, win32con.SW_RESTORE)
win32gui.SetWindowPos(handle, 0, 20, 20, 1500, 950, win32con.SWP_NOZORDER)
win32gui.ShowWindow(handle, win32con.SW_MAXIMIZE)
win32api.keybd_event(win32con.VK_MENU,0,0,0)
win32api.keybd_event(win32con.VK_MENU,0,win32con.KEYEVENTF_KEYUP,0)
win32gui.SetForegroundWindow(handle)
time.sleep(0.4)
left, top, right, bottom = win32gui.GetWindowRect(handle)
# Select the Tcl Console tab before its input (physical desktop coordinates).
win32api.SetCursorPos((left+int((right-left)*0.315), bottom-int((bottom-top)*0.043)))
win32api.mouse_event(win32con.MOUSEEVENTF_LEFTDOWN, 0, 0)
win32api.mouse_event(win32con.MOUSEEVENTF_LEFTUP, 0, 0)
time.sleep(0.2)
win32api.SetCursorPos((left + (right-left)//2, bottom-int((bottom-top)*0.069)))
win32api.mouse_event(win32con.MOUSEEVENTF_LEFTDOWN, 0, 0)
win32api.mouse_event(win32con.MOUSEEVENTF_LEFTUP, 0, 0)
if win32gui.GetForegroundWindow() != handle:
    raise SystemExit('TD did not retain foreground focus; command not sent')
win32clipboard.OpenClipboard()
try:
    win32api.keybd_event(win32con.VK_CONTROL, 0, 0, 0)
    win32api.keybd_event(ord('A'), 0, 0, 0)
    win32api.keybd_event(ord('A'), 0, win32con.KEYEVENTF_KEYUP, 0)
    win32api.keybd_event(win32con.VK_CONTROL, 0, win32con.KEYEVENTF_KEYUP, 0)
    previous = win32clipboard.GetClipboardData(win32con.CF_UNICODETEXT) if win32clipboard.IsClipboardFormatAvailable(win32con.CF_UNICODETEXT) else None
    win32clipboard.EmptyClipboard()
    win32clipboard.SetClipboardText(args.command, win32con.CF_UNICODETEXT)
finally:
    win32clipboard.CloseClipboard()
try:
    win32api.keybd_event(win32con.VK_CONTROL, 0, 0, 0)
    win32api.keybd_event(ord('V'), 0, 0, 0)
    win32api.keybd_event(ord('V'), 0, win32con.KEYEVENTF_KEYUP, 0)
    win32api.keybd_event(win32con.VK_CONTROL, 0, win32con.KEYEVENTF_KEYUP, 0)
    time.sleep(0.8)
    win32api.keybd_event(win32con.VK_RETURN, 0, 0, 0)
    win32api.keybd_event(win32con.VK_RETURN, 0, win32con.KEYEVENTF_KEYUP, 0)
    time.sleep(0.2)
finally:
    if previous is not None:
        win32clipboard.OpenClipboard()
        try:
            win32clipboard.EmptyClipboard()
            win32clipboard.SetClipboardText(previous, win32con.CF_UNICODETEXT)
        finally:
            win32clipboard.CloseClipboard()
