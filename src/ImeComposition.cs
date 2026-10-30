using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Automation;

namespace WubiCoach {
    public sealed class CompositionSnapshot {
        public string Text="", ContextBefore="", Source="";
        public bool Supported, HasContext;
        public string CodePrefix { get {return NormalizeCode(Text);} }
        public static string NormalizeCode(string text) {
            text=(text??"").Trim();
            return Regex.IsMatch(text,"^[a-yA-Y]{1,4}$")?text.ToUpperInvariant():"";
        }
    }
    internal static class ImeComposition {
        [ThreadStatic] static UiaClient automation;
        public static CompositionSnapshot Read(AutomationElement expected,IntPtr window) {
            var result=ReadTextEdit(expected);
            if(result.Text.Length>0)return result;
            var legacy=ReadImm(window);
            return legacy.Text.Length>0 || (!result.Supported && legacy.Supported)?legacy:result;
        }
        static CompositionSnapshot ReadTextEdit(AutomationElement expected) {
            var result=new CompositionSnapshot();
            UiaElement focus=null;object raw=null;UiaRange range=null,before=null;
            try {
                if(automation==null)automation=(UiaClient)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("FF48DBA4-60EF-4201-AA87-54103EEF594E")));
                focus=automation.GetFocusedElement();
                // Native and managed clients must be observing the same non-password control.
                if(focus==null || !expected.GetRuntimeId().SequenceEqual(focus.GetRuntimeId()) ||
                    Convert.ToBoolean(focus.GetCurrentPropertyValue(30019)))return result;
                var guid=new Guid("17E21576-996C-4870-99D9-BFF323380C06");
                if(focus.GetCurrentPatternAs(10032,ref guid,out raw)<0 || raw==null)return result;
                result.Supported=true;result.Source="UIA 预编辑";
                range=((UiaTextEdit)raw).GetActiveComposition();
                if(range==null)return result;
                result.Text=range.GetText(32)??"";
                before=range.Clone();
                before.MoveEndpointByRange(1,range,0);
                before.MoveEndpointByUnit(0,0,-80);
                result.ContextBefore=LearningEngine.Limit(before.GetText(512),80);result.HasContext=true;
            } catch(COMException) {} catch(InvalidCastException) {} catch(ElementNotAvailableException) {} catch(InvalidOperationException) {}
            finally {Release(before);Release(range);Release(raw);Release(focus);}
            return result;
        }
        static void Release(object value) {if(value!=null && Marshal.IsComObject(value))Marshal.ReleaseComObject(value);}
        static CompositionSnapshot ReadImm(IntPtr window) {
            var result=new CompositionSnapshot();
            uint pid;uint thread=Native.GetWindowThreadProcessId(window,out pid);
            var info=new GuiThreadInfo {Size=Marshal.SizeOf(typeof(GuiThreadInfo))};
            IntPtr target=GetGUIThreadInfo(thread,ref info)&&info.Focus!=IntPtr.Zero?info.Focus:window;
            IntPtr context=ImmGetContext(target);
            if(context==IntPtr.Zero)return result;
            try {
                // GCS_COMPSTR is UTF-16, but its API returns a BYTE count.
                int count=ImmGetCompositionStringW(context,8,null,0);
                if(count<0 || count>256 || count%2!=0)return result;
                result.Supported=true;result.Source="IMM 预编辑";
                if(count==0)return result;
                var bytes=new byte[count];int copied=ImmGetCompositionStringW(context,8,bytes,(uint)bytes.Length);
                if(copied>0 && copied<=bytes.Length && copied%2==0)result.Text=Encoding.Unicode.GetString(bytes,0,copied);
            } finally {ImmReleaseContext(target,context);}
            return result;
        }
        [StructLayout(LayoutKind.Sequential)] struct GuiThreadInfo {
            public int Size;public uint Flags;public IntPtr Active,Focus,Capture,MenuOwner,MoveSize,Caret;
            public int Left,Top,Right,Bottom;
        }
        [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint id,ref GuiThreadInfo info);
        [DllImport("imm32.dll")] static extern IntPtr ImmGetContext(IntPtr window);
        [DllImport("imm32.dll")] static extern bool ImmReleaseContext(IntPtr window,IntPtr context);
        [DllImport("imm32.dll",CharSet=CharSet.Unicode)] static extern int ImmGetCompositionStringW(IntPtr context,uint index,byte[] bytes,uint length);
    }

    // Prefix-only COM declarations. Uncalled slots preserve the Windows SDK vtable order.
    // Definitions checked against uiautomationclient.idl. Do not remove placeholder slots.
    [ComImport,Guid("30CBE57D-D9D0-452A-AB13-7AC5AC4825EE"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface UiaClient {
        void CompareElements();void CompareRuntimeIds();void GetRootElement();void ElementFromHandle();void ElementFromPoint();
        UiaElement GetFocusedElement();
    }
    [ComImport,Guid("D22108AA-8AC5-49A5-837B-37BBB3D7591E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface UiaElement {
        void SetFocus();
        [return:MarshalAs(UnmanagedType.SafeArray,SafeArraySubType=VarEnum.VT_I4)] int[] GetRuntimeId();
        void FindFirst();void FindAll();void FindFirstBuildCache();void FindAllBuildCache();void BuildUpdatedCache();
        [return:MarshalAs(UnmanagedType.Struct)] object GetCurrentPropertyValue(int property);
        void GetCurrentPropertyValueEx();void GetCachedPropertyValue();void GetCachedPropertyValueEx();
        [PreserveSig] int GetCurrentPatternAs(int pattern,ref Guid iid,[MarshalAs(UnmanagedType.IUnknown)]out object value);
    }
    [ComImport,Guid("17E21576-996C-4870-99D9-BFF323380C06"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface UiaTextEdit {
        void RangeFromPoint();void RangeFromChild();void GetSelection();void GetVisibleRanges();void GetDocumentRange();void GetSupportedTextSelection();
        UiaRange GetActiveComposition();
        UiaRange GetConversionTarget();
    }
    [ComImport,Guid("A543CC6A-F4AE-494B-8239-C814481187A8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface UiaRange {
        UiaRange Clone();void Compare();void CompareEndpoints();void ExpandToEnclosingUnit();void FindAttribute();void FindText();
        void GetAttributeValue();void GetBoundingRectangles();void GetEnclosingElement();
        [return:MarshalAs(UnmanagedType.BStr)] string GetText(int maxLength);
        void Move();int MoveEndpointByUnit(int endpoint,int unit,int count);
        void MoveEndpointByRange(int endpoint,UiaRange other,int otherEndpoint);
    }
}
