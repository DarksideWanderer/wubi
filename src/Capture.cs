using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Automation.Text;

namespace WubiCoach {
    public sealed class ContextSnapshot {
        public string Text="", Source="", Status="";
        public bool Available, Ignore;
        public IntPtr Window;
        public CompositionSnapshot Composition=new CompositionSnapshot();
        public string ControlIdentity="";
    }
    public sealed class ContextCapture : IDisposable {
        readonly Thread worker;
        readonly int ownPid=Process.GetCurrentProcess().Id;
        readonly KeyboardComposition keyboard;
        volatile bool stopping;
        volatile bool paused;
        public bool Paused {get {return paused;}set {paused=value;keyboard.Enabled=!value;}}
        public bool KeyboardAvailable {get {return keyboard.Installed;}}
        public event Action<ContextSnapshot> Updated;
        public event Action<bool> KeyboardVisibilityChanged;
        public ContextCapture() {
            keyboard=new KeyboardComposition();
            keyboard.KeyboardVisibilityChanged+=delegate(bool visible){if(KeyboardVisibilityChanged!=null)KeyboardVisibilityChanged(visible);};
            worker=new Thread(Run) { IsBackground=true,Name="Wubi UI Automation reader" };
            worker.SetApartmentState(ApartmentState.MTA);
            worker.Start();
        }
        void Run() {
            while(!stopping) {
                if(!Paused) {
                    ContextSnapshot result;
                    try { result=Read(ownPid);keyboard.Apply(result,result.ControlIdentity); }
                    catch(Exception ex) { keyboard.Clear();result=new ContextSnapshot {Status="读取暂不可用 · "+ex.GetType().Name}; }
                    if(!stopping && !Paused && Updated!=null) Updated(result);
                }
                Thread.Sleep(180);
            }
        }
        public static ContextSnapshot Read(int ignorePid) {
            var window=Native.GetForegroundWindow();
            uint pid; Native.GetWindowThreadProcessId(window,out pid);
            var result=new ContextSnapshot {Window=window};
            if(window==IntPtr.Zero || pid==ignorePid) {result.Ignore=true;return result;}
            try { result.Source=Process.GetProcessById((int)pid).ProcessName; } catch {result.Source="其他窗口";}
            var focus=AutomationElement.FocusedElement;
            if(focus==null || focus.Current.ProcessId!=(int)pid) {result.Status="等待目标输入框获得焦点";return result;}
            result.ControlIdentity=string.Join(".",focus.GetRuntimeId());
            // Check password state before requesting ANY text pattern or content.
            var element=focus;
            for(int depth=0;depth<5 && element!=null;depth++) {
                if(element.Current.IsPassword) { result.Status="密码输入框 · 已停止读取"; return result; }
                element=TreeWalker.ControlViewWalker.GetParent(element);
                if(element!=null && element.Current.ProcessId!=(int)pid) break;
            }
            result.Composition=ImeComposition.Read(focus,window);
            element=focus;
            for(int depth=0;depth<5 && element!=null;depth++) {
                if(element.Current.ProcessId!=(int)pid) break;
                object raw;
                if(element.TryGetCurrentPattern(TextPattern.Pattern,out raw)) {
                    var pattern=(TextPattern)raw;
                    var selection=pattern.GetSelection();
                    if(selection.Length>0) {
                        var range=selection[0].Clone();
                        range.MoveEndpointByRange(TextPatternRangeEndpoint.End,range,TextPatternRangeEndpoint.Start);
                        range.MoveEndpointByUnit(TextPatternRangeEndpoint.Start,TextUnit.Character,-80);
                        result.Text=LearningEngine.Limit(range.GetText(512),80);
                        if(result.Composition.HasContext) result.Text=result.Composition.ContextBefore;
                        else if(result.Composition.Text.Length>0 && result.Text.EndsWith(result.Composition.Text,StringComparison.Ordinal))
                            result.Text=result.Text.Substring(0,result.Text.Length-result.Composition.Text.Length);
                        if(Native.GetForegroundWindow()!=window) {result.Ignore=true;return result;}
                        result.Available=true; result.Status="实时读取 · 光标前最多 80 字"; return result;
                    }
                }
                // A ValuePattern without a caret position is deliberately not treated as surrounding text.
                element=TreeWalker.ControlViewWalker.GetParent(element);
            }
            result.Status="此输入框未提供光标上下文 · 可用手动上下文";
            return result;
        }
        public void Dispose() { stopping=true; Paused=true;keyboard.Dispose(); }
    }
    internal static class Native {
        [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
        [DllImport("user32.dll")] internal static extern int GetWindowLong(IntPtr hwnd,int index);
        [DllImport("user32.dll")] internal static extern int SetWindowLong(IntPtr hwnd,int index,int value);
        [DllImport("user32.dll")] internal static extern bool RegisterHotKey(IntPtr hwnd,int id,uint modifiers,uint key);
        [DllImport("user32.dll")] internal static extern bool UnregisterHotKey(IntPtr hwnd,int id);
        [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] internal static extern IntPtr SendMessage(IntPtr hwnd,uint message,IntPtr wparam,IntPtr lparam);
    }
}
