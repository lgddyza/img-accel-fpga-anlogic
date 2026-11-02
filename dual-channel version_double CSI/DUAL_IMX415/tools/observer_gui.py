"""Target one TD window; open project, save, or capture the actual desktop."""
import argparse,time
import win32api,win32con,win32gui,win32clipboard
from PIL import ImageGrab
p=argparse.ArgumentParser();p.add_argument('action',choices=['list','open','dialog','save','capture'])
p.add_argument('--hwnd',type=int);p.add_argument('--path');a=p.parse_args()
if a.action=='list':
    win32gui.EnumWindows(lambda h,_: print(h,win32gui.GetWindowText(h)) if 'Anlogic TD' in win32gui.GetWindowText(h) else None,None)
    raise SystemExit
win32gui.ShowWindow(a.hwnd,win32con.SW_MAXIMIZE)
win32api.keybd_event(win32con.VK_MENU,0,0,0)
win32api.keybd_event(win32con.VK_MENU,0,win32con.KEYEVENTF_KEYUP,0)
win32gui.SetForegroundWindow(a.hwnd);time.sleep(.5)
def key(code):
    win32api.keybd_event(code,0,0,0);win32api.keybd_event(code,0,win32con.KEYEVENTF_KEYUP,0)
def ctrl(code):
    win32api.keybd_event(win32con.VK_CONTROL,0,0,0);key(code)
    win32api.keybd_event(win32con.VK_CONTROL,0,win32con.KEYEVENTF_KEYUP,0)
if a.action=='capture': ImageGrab.grab().save(a.path)
elif a.action=='save': ctrl(ord('S'))
else:
    if a.action=='open': ctrl(ord('O'));time.sleep(.7)
    dialogs=[]
    def collect(h,_):
        if win32gui.GetWindowText(h)=='Open': dialogs.append(h)
        return True
    win32gui.EnumWindows(collect,None)
    # Dismiss only an error dialog owned by this TD project.
    for h in dialogs:
        try: error_control=win32gui.GetDlgItem(h,65535)
        except win32gui.error: error_control=0
        if error_control:
            win32gui.PostMessage(win32gui.GetDlgItem(h,1),win32con.BM_CLICK,0,0)
    time.sleep(.5)
    edits=[]
    def child(c,_):
        if win32gui.GetClassName(c)=='Edit' and win32gui.GetDlgCtrlID(c)==1148: edits.append(c)
        return True
    dialogs=[];win32gui.EnumWindows(collect,None)
    for h in dialogs: win32gui.EnumChildWindows(h,child,None)
    if len(edits)!=1: raise SystemExit(f'Expected one project filename edit, got {edits}')
    win32gui.SendMessage(edits[0],win32con.WM_SETTEXT,0,a.path.replace('/','\\'))
    parent=win32gui.GetAncestor(edits[0],win32con.GA_ROOT)
    win32gui.PostMessage(win32gui.GetDlgItem(parent,1),win32con.BM_CLICK,0,0)
    time.sleep(3)
