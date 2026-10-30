using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace WubiCoach {
    // Stores only the pending code (at most four letters), never an input history.
    // The hook just queues small key tokens. UI Automation work stays off the hook thread.
    public sealed class KeyboardComposition : IDisposable {
        struct KeyToken {public int Key;public IntPtr Window,Focus;public bool Shortcut;}
        readonly object gate=new object();
        readonly Queue<KeyToken> pending=new Queue<KeyToken>();
        readonly HookProc callback;
        readonly int ignoredPid;
        IntPtr hook;
        bool keyboardVisible;
        readonly HoldKeyboardShortcut holdShortcut=new HoldKeyboardShortcut();
        public event Action<bool> KeyboardVisibilityChanged;
        IntPtr previousWindow,previousFocus;
        string code="",previousText="",previousControl="";
        bool suppressNative;
        volatile bool enabled=true;
        public bool Enabled {get {return enabled;}set {enabled=value;Clear();}}
        public bool Installed {get {return hook!=IntPtr.Zero;}}
        public KeyboardComposition():this(Process.GetCurrentProcess().Id) {}
        public KeyboardComposition(int ignorePid) {
            ignoredPid=ignorePid;callback=OnKey;
            hook=SetWindowsHookEx(13,callback,GetModuleHandle(null),0);
        }
        IntPtr OnKey(int n,IntPtr message,IntPtr data) {
            int kind=message.ToInt32();
            if(n>=0 && (kind==0x100||kind==0x104||kind==0x101||kind==0x105)) {
                var key=(KeyData)Marshal.PtrToStructure(data,typeof(KeyData));
                bool down=kind==0x100||kind==0x104;
                bool modifier=key.Key==0x10||key.Key==0x11||key.Key==0x12||(key.Key>=0xA0&&key.Key<=0xA5)||key.Key==0x5B||key.Key==0x5C;
                bool required=Down(0x11)&&Down(0x12)&&!Down(0x10)&&!Down(0x5B)&&!Down(0x5C);
                bool consumed=holdShortcut.Handle((int)key.Key,down,required);
                if(modifier)holdShortcut.ModifiersChanged(required&&down);
                if(keyboardVisible!=holdShortcut.Visible) {keyboardVisible=holdShortcut.Visible;if(KeyboardVisibilityChanged!=null)KeyboardVisibilityChanged(keyboardVisible);}
                if(consumed)return new IntPtr(1);
                // Modifier events must not erase the pending code when peeking at roots.
                if(modifier)return CallNextHookEx(hook,n,message,data);
                if(!enabled || (kind!=0x100 && kind!=0x104))return CallNextHookEx(hook,n,message,data);
                IntPtr window=Native.GetForegroundWindow();uint pid;
                uint thread=Native.GetWindowThreadProcessId(window,out pid);
                if(pid!=ignoredPid && window!=IntPtr.Zero) {
                    var info=new GuiInfo {Size=Marshal.SizeOf(typeof(GuiInfo))};GetGUIThreadInfo(thread,ref info);
                    bool shortcut=Down(0x11)||Down(0x12)||Down(0x5B)||Down(0x5C);
                    lock(gate) {
                        // Bound memory, including a stalled provider or an unresponsive UI.
                        if(pending.Count>=32)pending.Clear();
                        pending.Enqueue(new KeyToken {Key=(int)key.Key,Window=window,Focus=info.Focus,Shortcut=shortcut});
                    }
                }
            }
            return CallNextHookEx(hook,n,message,data);
        }
        static bool Down(int key) {return (GetAsyncKeyState(key)&0x8000)!=0;}
        public void Apply(ContextSnapshot snapshot,string control) {
            lock(gate) {
                if(snapshot.Ignore||!snapshot.Available) {Reset();pending.Clear();return;}
                uint pid;uint thread=Native.GetWindowThreadProcessId(snapshot.Window,out pid);
                var info=new GuiInfo {Size=Marshal.SizeOf(typeof(GuiInfo))};GetGUIThreadInfo(thread,ref info);
                if(previousWindow!=snapshot.Window||previousFocus!=info.Focus||previousControl!=control)Reset();
                previousWindow=snapshot.Window;previousFocus=info.Focus;previousControl=control;
                bool freshLetter=false;
                while(pending.Count>0) {
                    var item=pending.Dequeue();
                    if(item.Window!=snapshot.Window||item.Focus!=info.Focus)continue;
                    if(item.Shortcut) {code="";suppressNative=true;continue;}
                    if(item.Key>=0x41 && item.Key<=0x59) {
                        // Four-code auto-commit: a fifth letter starts a new character.
                        if(code.Length>=4)code="";
                        code+=(char)item.Key;suppressNative=false;
                        freshLetter=true;
                    } else if(item.Key==8) {if(code.Length>0)code=code.Substring(0,code.Length-1);suppressNative=code.Length==0;}
                    else {code="";suppressNative=true;}
                }
                string committed=snapshot.Text;
                if(code.Length>0 && !snapshot.Composition.HasContext && committed.EndsWith(code,StringComparison.OrdinalIgnoreCase))
                    committed=committed.Substring(0,committed.Length-code.Length);
                // A newly committed character invalidates the previous inferred code.
                if(previousText.Length>0 && committed!=previousText && code.Length>0 && !snapshot.Composition.HasContext && !freshLetter)code="";
                previousText=committed;snapshot.Text=committed;
                if(snapshot.Composition.Text.Length==0)suppressNative=false;
                if(suppressNative) snapshot.Composition=new CompositionSnapshot {Supported=true,Source="按键监听"};
                else if(snapshot.Composition.CodePrefix.Length==0 && code.Length>0)
                    snapshot.Composition=new CompositionSnapshot {Text=code,Supported=true,Source="按键推测"};
            }
        }
        void Reset() {code="";previousText="";previousWindow=IntPtr.Zero;previousFocus=IntPtr.Zero;previousControl="";suppressNative=false;}
        public void Clear() {lock(gate){Reset();pending.Clear();}}
        public void Dispose() {enabled=false;if(hook!=IntPtr.Zero){UnhookWindowsHookEx(hook);hook=IntPtr.Zero;}if(keyboardVisible&&KeyboardVisibilityChanged!=null)KeyboardVisibilityChanged(false);Clear();}
        [StructLayout(LayoutKind.Sequential)] struct KeyData {public uint Key,Scan,Flags,Time;public UIntPtr Extra;}
        [StructLayout(LayoutKind.Sequential)] struct GuiInfo {public int Size;public uint Flags;public IntPtr Active,Focus,Capture,MenuOwner,MoveSize,Caret;public int Left,Top,Right,Bottom;}
        delegate IntPtr HookProc(int n,IntPtr message,IntPtr data);
        [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id,HookProc callback,IntPtr module,uint thread);
        [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int n,IntPtr message,IntPtr data);
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GuiInfo info);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    }
}
