using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Windows.Interop;

namespace WubiCoach {
    static class Program {
        [STAThread] static int Main(string[] args) {
            string directory=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"data");
            try {
                if(args.Contains("--fixture")) {RunFixture(args);return 0;}
                if(args.Contains("--capture-test")) {CaptureTest(args);return 0;}
                var model=new LearningEngine(directory);
                if(args.Contains("--self-test")) {SelfTest(model,args);return 0;}
                if(args.Contains("--keyboard-test")) {KeyboardTest(model,args);return 0;}
                var app=new Application();
                bool preview=args.Contains("--render");
                var window=new MainWindow(model,directory,preview);
                if(preview) {
                    if(args.Contains("--ime-demo"))window.Demo("直","R");else window.Demo("我想学习");
                    if(args.Contains("--keyboard-demo"))window.SetKeyboardVisible(true);
                    var board=window.Artboard;
                    board.Measure(new Size(800,double.PositiveInfinity));
                    board.Arrange(new Rect(0,0,800,board.DesiredSize.Height));
                    board.UpdateLayout();
                    int height=(int)Math.Ceiling(board.RenderSize.Height);
                    var bitmap=new RenderTargetBitmap(800,height,96,96,PixelFormats.Pbgra32);bitmap.Render(board);
                    var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));
                    using(var stream=File.Create(args[args.Length-1]))png.Save(stream);
                    return 0;
                }
                app.Run(window);Environment.Exit(0);return 0;
            } catch(Exception ex) {
                if(args.Length>0) File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-error.log"),ex.ToString());
                else MessageBox.Show(ex.Message+"\n请确认 data 文件夹与程序放在一起。","五笔伴学启动失败");
                return 1;
            }
        }
        static void Check(bool value,string label,StringBuilder log) {if(!value)throw new Exception("FAIL: "+label);log.AppendLine("PASS: "+label);}
        static void SelfTest(LearningEngine model,string[] args) {
            var log=new StringBuilder();
            Check(model.Characters.Count>13000,"over 13,000 character codes",log);
            Check(model.Characters.Values.Count(c=>c.Units.Length>0)>11000,"over 11,000 actual decompositions",log);
            Check(model.PhraseCount>10000,"real phrase dictionary loaded",log);
            foreach(var p in new[]{new[]{"你","WQIY"},new[]{"好","VBG"},new[]{"中","KHK"},new[]{"国","LGYI"},new[]{"学","IPBF"}})
                Check(model.Characters[p[0]].Code==p[1],"code "+p[0]+" "+p[1],log);
            Check(model.Characters["好"].Identification,"identification code marked",log);
            Check(model.Characters["人"].KeyUnit,"key-name character marked",log);
            Check(model.Characters["一"].StrokeUnit,"single-stroke character marked",log);
            Check(model.Predict("你好").Count==18,"eighteen unique next characters",log);
            Check(model.Predict("我想学").Any(p=>p.Info.Character=="习"),"learning continuation",log);
            Check(model.Predict("谢谢").Any(p=>p.Info.Character=="你"),"thanks continuation",log);
            Check(model.Predict("中华人民共和")[0].Info.Character=="国","longest suffix dominates",log);
            Check(model.Predict("xyz").Count==18,"unknown context fallback",log);
            Check(model.Predict("直","r")[0].Info.Character=="接","zhi + r predicts jie first",log);
            Check(model.Predict("直","ru")[0].Info.Character=="接","prefix ru retains jie",log);
            Check(model.Predict("直","ruvg").Count==1&&model.Predict("直","ruvg")[0].Info.Character=="接","full code ruvg narrows to jie",log);
            Check(model.Predict("直","R").All(c=>c.Info.Code.StartsWith("R")),"all eighteen r candidates obey code prefix",log);
            Check(model.Predict("直","R").Count==18,"eighteen code-filtered candidates",log);
            Check(model.Predict("直","").Count==18,"empty preedit restores context prediction",log);
            Check(model.Predict("直","AYYY").Count==0,"no-match prefix does not show unrelated characters",log);
            Check(CompositionSnapshot.NormalizeCode(" rU ")=="RU"&&CompositionSnapshot.NormalizeCode("123")==""&&CompositionSnapshot.NormalizeCode("abcde")=="","bounded five-stroke prefix normalization",log);
            Check(LearningEngine.Limit(new string('甲',90)+"乙",80).Length==80,"context bounded to 80",log);
            string fontDirectory=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"data")+Path.DirectorySeparatorChar;
            var fontFamily=Fonts.GetFontFamilies(new Uri(fontDirectory)).First();
            GlyphTypeface glyphs;
            Check(new Typeface(fontFamily,FontStyles.Normal,FontWeights.Normal,FontStretches.Normal).TryGetGlyphTypeface(out glyphs),"dedicated radical font loaded",log);
            Check(model.Characters.Values.SelectMany(c=>c.Units).Distinct().Where(c=>c>='\uE000'&&c<='\uF8FF').All(c=>glyphs.CharacterToGlyphMap.ContainsKey(c)),"every custom radical glyph exists in font (standard Han glyphs use WPF fallback)",log);
            foreach(var text in new[]{"","我想","中国","\n","hello","学习五笔"}) {
                var items=model.Predict(text);Check(items.Count==18&&items.Select(p=>p.Info.Character).Distinct().Count()==18,"valid unique candidates "+text,log);
            }
            foreach(var line in File.ReadLines(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"..","tests","fixtures","predictions18.tsv"),Encoding.UTF8).Skip(1)) {
                var p=line.Split('\t');
                Check(string.Join(",",model.Predict(p[0],p[1]).Select(item=>item.Info.Character))==p[2],"shared eighteen-candidate order "+p[0]+" + "+p[1],log);
            }
            PinyinTests(model,log);
            log.AppendLine("Characters="+model.Characters.Count+"; phrases="+model.PhraseCount);
            File.WriteAllText(args[args.Length-1],log.ToString(),Encoding.UTF8);
        }
        static void PinyinTests(LearningEngine model,StringBuilder log) {
            var index=model.Pinyin;
            Check(index.CharacterCount==44440,"all 44,440 pinyin characters loaded",log);
            string fixture=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"..","tests","fixtures","pinyin.tsv");
            foreach(var line in File.ReadLines(fixture,Encoding.UTF8).Skip(1)) {
                var p=line.Split('\t');var items=index.Search(p[0]);
                Check(items.Count==int.Parse(p[1])&&items.Select(i=>i.Character).Distinct().Count()==items.Count,"complete unique pinyin "+p[0],log);
                Check(items.All(i=>(i.Character.Length==1||i.Character.Length==2&&char.IsSurrogatePair(i.Character,0))&&i.Readings.Contains(p[0])),"single-character readings "+p[0],log);
                using(var hash=SHA256.Create()) {
                    string digest=BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(string.Concat(items.Select(i=>i.Character))))).Replace("-","").ToLowerInvariant();
                    Check(digest==p[2],"shared macOS result order "+p[0],log);
                }
            }
            Check(index.Search(" NI ").Select(i=>i.Character).SequenceEqual(index.Search("ni").Select(i=>i.Character)),"pinyin ignores case and surrounding spaces",log);
            Check(index.Search("lue").Select(i=>i.Character).SequenceEqual(index.Search("lve").Select(i=>i.Character)),"lue alias",log);
            Check(index.Search("nue").Select(i=>i.Character).SequenceEqual(index.Search("nve").Select(i=>i.Character)),"nue alias",log);
            Check(index.Search("lv").Any(i=>i.Character=="吕")&&!index.Search("lu").Any(i=>i.Character=="吕"),"lv distinct from lu",log);
            Check(index.Search("xing").Any(i=>i.Character=="行")&&index.Search("hang").Any(i=>i.Character=="行"),"all polyphonic readings indexed",log);
            Check(index.Search("ji").Any(i=>i.Character.Length==2),"supplementary characters retained",log);
            Check(index.Search("shi").Count>5&&index.Search("shi").Any(i=>!model.Characters.ContainsKey(i.Character)),"uncapped results include characters outside Wubi table",log);
            foreach(var q in new[]{"","nihao","ni3","你好","ni hao","ni'hao","!!!","ß"})Check(index.Search(q).Count==0,"invalid or non-syllable query "+q,log);
            var hold=new HoldKeyboardShortcut();
            Check(hold.Handle(0x4B,true,true)&&hold.Visible,"Ctrl+Alt+K hold",log);
            Check(hold.Handle(0x4B,true,true)&&hold.Visible,"repeat stays visible",log);
            hold.ModifiersChanged(false);Check(!hold.Visible&&hold.Pressed,"modifier release hides roots",log);
            Check(hold.Handle(0x4B,true,false)&&!hold.Visible,"repeat after modifier release stays consumed",log);
            Check(hold.Handle(0x4B,false,false)&&!hold.Pressed,"K release consumed",log);
            Check(!hold.Handle(0x4B,true,false),"ordinary K passes through",log);
            Check(!hold.Handle(0x4B,true,true)&&!hold.Visible,"adding modifiers to held K cannot activate",log);
            hold.Reset();Check(!hold.Handle(0x77,true,true),"F8 passes through",log);
        }
        static void RunFixture(string[] args) {
            var app=new Application();var window=new Window {Title="WubiCoach automated capture fixture",Width=460,Height=240,Topmost=true};
            var panel=new StackPanel();
            var box=new TextBox {Text="这是已上屏的中文上下文，光标后面的文字不应被读取",AcceptsReturn=true,Height=100};
            var password=new PasswordBox {Password="test-only-password",Height=35};panel.Children.Add(box);panel.Children.Add(password);window.Content=panel;
            window.Loaded+=delegate {window.Activate();box.Focus();box.CaretIndex="这是已上屏的中文上下文".Length;};
            var timer=new DispatcherTimer {Interval=TimeSpan.FromSeconds(14)};
            timer.Tick+=delegate {password.Focus();timer.Stop();};timer.Start();
            var closeTimer=new DispatcherTimer {Interval=TimeSpan.FromSeconds(23)};closeTimer.Tick+=delegate {window.Close();};closeTimer.Start();app.Run(window);
        }
        static void KeyboardTest(LearningEngine model,string[] args) {
            var app=new Application();
            var window=new Window {Title="WubiCoach keyboard listener test",Width=470,Height=180,Topmost=true};
            window.Content=new TextBox {Text="直",AcceptsReturn=true,FontSize=24};
            KeyboardComposition listener=null;var log=new StringBuilder();int phase=0;Exception failure=null;bool keyboardVisible=false;
            var timer=new DispatcherTimer {Interval=TimeSpan.FromMilliseconds(300)};
            Action<int> key=delegate(int vk) {
                if(Native.GetForegroundWindow()!=new WindowInteropHelper(window).Handle)throw new Exception("Test fixture lost focus; no key was sent.");
                KeybdEvent((byte)vk,0,0,UIntPtr.Zero);KeybdEvent((byte)vk,0,2,UIntPtr.Zero);
            };
            timer.Tick+=delegate {
                try {
                    var snapshot=new ContextSnapshot {Available=true,Window=new WindowInteropHelper(window).Handle,Text="直"};
                    listener.Apply(snapshot,"fixture");
                    if(phase==0) {Check(listener.Installed,"native keyboard hook installed",log);key(0x52);}
                    if(phase==1) {Check(snapshot.Composition.CodePrefix=="R","native hook receives R",log);Check(model.Predict(snapshot.Text,snapshot.Composition.CodePrefix)[0].Info.Character=="接","live R + context zhi selects jie",log);key(0x55);}
                    if(phase==2) {Check(snapshot.Composition.CodePrefix=="RU","second letter updates prefix",log);key(8);}
                    if(phase==3) {Check(snapshot.Composition.CodePrefix=="R","backspace removes one letter",log);key(13);}
                    if(phase==4) {Check(snapshot.Composition.CodePrefix=="","enter clears prefix",log);key(0x52);}
                    if(phase==5) {Check(snapshot.Composition.CodePrefix=="R","new code after enter",log);key(0x20);}
                    if(phase==6) {Check(snapshot.Composition.CodePrefix=="","space selection clears prefix",log);listener.Enabled=false;key(0x52);}
                    if(phase==7) {Check(snapshot.Composition.CodePrefix=="","paused listener ignores keys",log);listener.Enabled=true;key(0x52);}
                    if(phase==8) {Check(snapshot.Composition.CodePrefix=="R","resume starts fresh",log);snapshot.Available=false;listener.Apply(snapshot,"password");
                        var clean=new ContextSnapshot {Available=true,Window=snapshot.Window,Text="直"};listener.Apply(clean,"fixture");Check(clean.Composition.CodePrefix=="","unavailable/password context discards pending code",log);
                        key(0x52);}
                    if(phase==9) {Check(snapshot.Composition.CodePrefix=="R","code ready before holding Ctrl+Alt+K",log);KeybdEvent(0x11,0,0,UIntPtr.Zero);KeybdEvent(0x12,0,0,UIntPtr.Zero);KeybdEvent(0x4B,0,0,UIntPtr.Zero);}
                    if(phase==10) {Check(keyboardVisible,"holding Ctrl+Alt+K switches to keyboard",log);Check(snapshot.Composition.CodePrefix=="R","Ctrl+Alt+K press preserves pending code",log);KeybdEvent(0x4B,0,0,UIntPtr.Zero);}
                    if(phase==11) {Check(keyboardVisible,"Ctrl+Alt+K autorepeat keeps keyboard visible",log);KeybdEvent(0x12,0,2,UIntPtr.Zero);KeybdEvent(0x4B,0,2,UIntPtr.Zero);KeybdEvent(0x11,0,2,UIntPtr.Zero);}
                    if(phase==12) {Check(!keyboardVisible,"releasing Ctrl+Alt+K restores candidates",log);Check(snapshot.Composition.CodePrefix=="R","Ctrl+Alt+K release preserves pending code",log);
                        File.WriteAllText(args[args.Length-1],log.ToString(),Encoding.UTF8);window.Close();}
                    phase++;
                } catch(Exception ex) {failure=ex;window.Close();}
            };
            window.Loaded+=delegate {window.Activate();((TextBox)window.Content).Focus();listener=new KeyboardComposition(-1);listener.KeyboardVisibilityChanged+=delegate(bool visible){keyboardVisible=visible;};timer.Start();};
            window.Closed+=delegate {timer.Stop();if(listener!=null)listener.Dispose();};app.Run(window);
            if(failure!=null)throw failure;
        }
        [System.Runtime.InteropServices.DllImport("user32.dll",EntryPoint="keybd_event")] static extern void KeybdEvent(byte vk,byte scan,uint flags,UIntPtr extra);
        static void CaptureTest(string[] args) {
            var log=new StringBuilder();
            var snapshot=ContextCapture.Read(-1);
            log.AppendLine("Source="+snapshot.Source+"; Status="+snapshot.Status+"; Text="+snapshot.Text);
            if(args.Contains("--password")) Check(!snapshot.Available&&snapshot.Text==""&&snapshot.Status.Contains("密码"),"password field excluded",log);
            else {
                Check(snapshot.Available&&snapshot.Text=="这是已上屏的中文上下文","cross-process committed Chinese before caret; suffix excluded",log);
                var foreground=Native.GetForegroundWindow();
                string data=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"data");
                var overlay=new MainWindow(new LearningEngine(data),data,true);overlay.Show();
                var hwnd=new WindowInteropHelper(overlay).Handle;
                Check(Native.GetForegroundWindow()==foreground,"showing overlay preserves typing focus",log);
                Check((Native.GetWindowLong(hwnd,-20)&0x08000000)!=0,"overlay has WS_EX_NOACTIVATE",log);
                Check(Native.SendMessage(hwnd,0x21,foreground,IntPtr.Zero).ToInt32()==3,"overlay mouse activation returns MA_NOACTIVATE",log);
                Check(overlay.Topmost,"overlay is topmost by default",log);
                Check(!overlay.KeyboardVisible,"keyboard is collapsed by default",log);
                Check(overlay.CandidatesVisible,"candidates visible by default",log);
                double compactHeight=overlay.Height;
                double compactWidth=overlay.Width;
                overlay.SetKeyboardVisible(true);
                Check(overlay.KeyboardVisible&&!overlay.CandidatesVisible,"holding Ctrl+Alt+K replaces candidates with keyboard",log);
                Check(overlay.Height==compactHeight&&overlay.Width==compactWidth,"keyboard mode keeps window dimensions unchanged",log);
                overlay.SetKeyboardVisible(false);
                Check(!overlay.KeyboardVisible&&overlay.CandidatesVisible,"release restores candidates and hides keyboard",log);
                Check(overlay.Height==compactHeight&&overlay.Width==compactWidth,"candidate mode keeps window dimensions unchanged",log);
                Check(Native.GetForegroundWindow()==foreground,"view switch preserves input focus",log);
                overlay.Close();
            }
            File.WriteAllText(args[args.Length-1],log.ToString(),Encoding.UTF8);
        }
    }
}
