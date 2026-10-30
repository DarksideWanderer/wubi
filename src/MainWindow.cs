using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace WubiCoach {
    public sealed class MainWindow : Window {
        readonly LearningEngine engine;
        readonly FontFamily rootFont;
        readonly Dictionary<char, Border> keys=new Dictionary<char,Border>();
        readonly Dictionary<char,string> rootKeys=new Dictionary<char,string>();
        readonly StackPanel candidatePanel=new StackPanel {MinHeight=220};
        readonly StackPanel candidateView=new StackPanel();
        readonly StackPanel keyboardPanel=new StackPanel {Visibility=Visibility.Collapsed};
        readonly TextBlock contextText, sourceText, detailText, tipText;
        readonly Button pinButton, liveButton,codeButton;
        ContextCapture capture;
        bool paused, manual, closing,codeEnabled=true;
        string lastContext="",lastStatus="", selectedCode="",lastPrefix="",lastComposition="";
        List<Candidate> candidates;
        IntPtr handle;
        static readonly Brush Ink=BrushOf("#1E3432"), Muted=BrushOf("#697B78"), Accent=BrushOf("#007D72");
        public UIElement Artboard {get;private set;}
        public static Brush BrushOf(string s) { return (Brush)new BrushConverter().ConvertFromString(s); }
        public MainWindow(LearningEngine model,string dataDirectory,bool preview) {
            engine=model;
            rootFont=Fonts.GetFontFamilies(new Uri(Path.GetFullPath(dataDirectory)+Path.DirectorySeparatorChar)).FirstOrDefault() ?? new FontFamily("Microsoft YaHei UI");
            MakeRootKeys();
            foreach(var line in File.ReadLines(Path.Combine(dataDirectory,"keyboard.tsv"),Encoding.UTF8)) {
                var rootColumns=line.Split('\t');
                if(rootColumns.Length<4 || rootColumns[0].Length==0 || rootColumns[0][0]<'A' || rootColumns[0][0]>'Y')continue;
                rootKeys[rootColumns[0][0]]=string.Concat(Regex.Matches(string.Join("",rootColumns.Skip(1).Take(3).ToArray()),"[\uE000-\uF8FF]").Cast<Match>().Select(m=>m.Value).Distinct().ToArray());
            }
            Title="五笔伴学 · 86版"; Width=900; Height=520; MinWidth=720;MinHeight=400;
            Background=BrushOf("#F3F5F0"); FontFamily=new FontFamily("Microsoft YaHei UI"); Foreground=Ink;
            WindowStartupLocation=WindowStartupLocation.CenterScreen; Topmost=true;ShowActivated=false;
            var board=new StackPanel {Width=960,Margin=new Thickness(22,12,22,16)};
            var header=new DockPanel {Margin=new Thickness(0,0,0,14)};
            var actions=new StackPanel {Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center};
            pinButton=ActionButton("● 已置顶",delegate {Topmost=!Topmost;pinButton.Content=Topmost?"● 已置顶":"○ 置顶";});
            liveButton=ActionButton("Ⅱ 暂停",delegate {ToggleLive();});
            actions.Children.Add(pinButton); actions.Children.Add(liveButton);
            codeButton=ActionButton("编码提示：开",delegate {codeEnabled=!codeEnabled;codeButton.Content=codeEnabled?"编码提示：开":"编码提示：关";ShowPredictions(lastContext,codeEnabled?lastPrefix:"");});
            actions.Children.Add(codeButton);
            actions.Children.Add(ActionButton("手动 / 查字",delegate {OpenManual();}));
            actions.Children.Add(ActionButton("帮助",delegate {ShowHelp();}));
            DockPanel.SetDock(actions,Dock.Right);header.Children.Add(actions);
            var brand=new StackPanel();brand.Children.Add(Text("五笔伴学",27,Ink,FontWeights.Bold));
            brand.Children.Add(Text("WUBI COMPANION   /   86 版 · 离线联想",11,Muted,FontWeights.Normal));
            header.Children.Add(brand);board.Children.Add(header);
            var contentSlot=new Grid {Height=410};
            keyboardPanel.VerticalAlignment=VerticalAlignment.Center;
            contentSlot.Children.Add(candidateView);contentSlot.Children.Add(keyboardPanel);board.Children.Add(contentSlot);
            var contextBox=new Border {Background=BrushOf("#E4EEEA"),CornerRadius=new CornerRadius(12),Padding=new Thickness(16,11,16,11),Margin=new Thickness(0,0,0,13)};
            var contextStack=new StackPanel();sourceText=Text("等待其他窗口的输入框 · 光标前最多 80 字",11,Accent,FontWeights.SemiBold);
            contextText=Text("在其他窗口输入中文，输入法上屏后会在这里显示上下文。",15,Ink,FontWeights.Normal);contextText.Margin=new Thickness(0,7,0,0);contextText.TextTrimming=TextTrimming.CharacterEllipsis;
            contextStack.Children.Add(sourceText);contextStack.Children.Add(contextText);contextBox.Child=contextStack;candidateView.Children.Add(contextBox);
            var labelRow=new DockPanel {Margin=new Thickness(3,0,3,8)};
            var counter=Text(engine.Characters.Count.ToString("N0")+" 字 · "+engine.PhraseCount.ToString("N0")+" 词",11,Muted,FontWeights.Normal);
            DockPanel.SetDock(counter,Dock.Right);labelRow.Children.Add(counter);
            labelRow.Children.Add(Text("接下来，可能想打…",16,Ink,FontWeights.Bold));candidateView.Children.Add(labelRow);
            var columns=new Grid {Margin=new Thickness(12,0,12,5)};
            foreach(double w in new[]{58.0,70,115,125,315,230}) columns.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(w)});
            string[] names={"排序","汉字","完整编码","可用简码","取码字根 / 识别码","联想依据"};
            for(int i=0;i<names.Length;i++) {var t=Text(names[i],11,Muted,FontWeights.Normal);Grid.SetColumn(t,i);columns.Children.Add(t);}candidateView.Children.Add(columns);
            candidateView.Children.Add(candidatePanel);
            var detailBox=new Border {CornerRadius=new CornerRadius(9),Background=BrushOf("#D9EAE2"),Padding=new Thickness(13,10,13,10),Margin=new Thickness(0,8,0,12)};
            detailText=Text("选择一个候选，查看取码规则。",13,Ink,FontWeights.Normal);detailText.TextWrapping=TextWrapping.Wrap;detailBox.Child=detailText;candidateView.Children.Add(detailBox);
            var keyboardTitle=new DockPanel {Margin=new Thickness(3,0,3,5)};
            var legend=new StackPanel {Orientation=Orientation.Horizontal};
            foreach(var pair in new[]{"横区 · GFDSA","竖区 · HJKLM","撇区 · TREWQ","捺区 · YUIOP","折区 · NBVCX"}) {
                char letter=pair[pair.Length-1];var t=Text(pair,10,Zone(letter),FontWeights.SemiBold);t.Margin=new Thickness(14,0,0,0);legend.Children.Add(t);
            }
            DockPanel.SetDock(legend,Dock.Right);keyboardTitle.Children.Add(legend);keyboardTitle.Children.Add(Text("字根键盘 · 基本字根",15,Ink,FontWeights.Bold));keyboardPanel.Children.Add(keyboardTitle);
            foreach(var row in new[]{"QWERTYUIOP","ASDFGHJKL","ZXCVBNM"}) {
                var rowPanel=new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Center};
                foreach(char c in row) rowPanel.Children.Add(Key(c));keyboardPanel.Children.Add(rowPanel);
            }
            tipText=Text("按住 F8 切换字根键盘，松开恢复候选；窗口大小不变。Ctrl+Alt+W 暂停 / 继续，Ctrl+Alt+T 置顶。",11,Muted,FontWeights.Normal);tipText.Margin=new Thickness(4,10,0,0);board.Children.Add(tipText);
            Artboard=new Border {Background=Background,Child=board};
            Content=new Viewbox {Stretch=Stretch.Uniform,StretchDirection=StretchDirection.Both,Child=(UIElement)Artboard};
            ShowPredictions("");
            SourceInitialized+=delegate {
                handle=new WindowInteropHelper(this).Handle;
                Native.SetWindowLong(handle,-20,Native.GetWindowLong(handle,-20)|0x08000000);
                HwndSource.FromHwnd(handle).AddHook(WindowHook);
                bool a=Native.RegisterHotKey(handle,1,0x4003,0x57),b=Native.RegisterHotKey(handle,2,0x4003,0x54);
                if(!a||!b) tipText.Text="部分快捷键已被其他程序占用；可使用窗口上的按钮。";
            };
            if(!preview) Loaded+=delegate {capture=new ContextCapture();capture.Updated+=OnSnapshot;capture.KeyboardVisibilityChanged+=SetKeyboardVisible;if(!capture.KeyboardAvailable)tipText.Text="按键监听未能启动；F8 暂不可用，仍会尝试读取输入法预编辑。";};
            Closed+=delegate {closing=true;if(capture!=null)capture.Dispose();Native.UnregisterHotKey(handle,1);Native.UnregisterHotKey(handle,2);};
        }
        public bool KeyboardVisible {get {return keyboardPanel.Visibility==Visibility.Visible;}}
        public bool CandidatesVisible {get {return candidateView.Visibility==Visibility.Visible;}}
        public void SetKeyboardVisible(bool visible) {
            if(closing||KeyboardVisible==visible)return;
            keyboardPanel.Visibility=visible?Visibility.Visible:Visibility.Collapsed;
            candidateView.Visibility=visible?Visibility.Collapsed:Visibility.Visible;
        }
        IntPtr WindowHook(IntPtr hwnd,int msg,IntPtr wp,IntPtr lp,ref bool handled) {
            if(msg==0x21) {handled=true;return new IntPtr(3);} // MA_NOACTIVATE: clicks still reach the controls.
            if(msg==0x312) {if(wp.ToInt32()==1) ToggleLive();else if(wp.ToInt32()==2)pinButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));handled=true;}
            return IntPtr.Zero;
        }
        void ToggleLive() {
            if(manual) {manual=false;paused=false;} else paused=!paused;
            if(capture!=null)capture.Paused=paused;
            liveButton.Content=paused?"▶ 继续":"Ⅱ 暂停";
            if(paused) {ClearContext("已暂停读取 · 上下文已清除");} else {lastContext="\0";sourceText.Text="等待其他窗口的输入框";}
        }
        void OnSnapshot(ContextSnapshot snapshot) {
            if(closing || snapshot.Ignore)return;
            Dispatcher.BeginInvoke(new Action(delegate {
                if(closing || paused || manual)return;
                if(!snapshot.Available) {if(lastStatus!=snapshot.Status)ClearContext(snapshot.Source+" · "+snapshot.Status);lastStatus=snapshot.Status;return;}
                lastStatus="";sourceText.Text=snapshot.Source+" · "+snapshot.Status+" · "+(snapshot.Composition.Text.Length>0?snapshot.Composition.Source:"按键监听");
                string prefix=snapshot.Composition.CodePrefix;
                if(lastContext==snapshot.Text && lastPrefix==prefix && lastComposition==snapshot.Composition.Text)return;
                lastContext=snapshot.Text;lastPrefix=prefix;lastComposition=snapshot.Composition.Text;
                UpdateContextDisplay();ShowPredictions(lastContext,codeEnabled?lastPrefix:"");
            }));
        }
        void UpdateContextDisplay() {
            contextText.Text=(lastContext.Length==0?"光标前暂无文字。":lastContext.Replace("\n"," ↵ "))+
                (lastComposition.Length>0?"    │    正在输入："+lastComposition+(lastPrefix.Length==0?"（非五笔码，不筛选）":""):"");
        }
        void ClearContext(string status) {lastContext="";lastPrefix="";lastComposition="";contextText.Text="—";sourceText.Text=status;ShowPredictions("");}
        void ShowPredictions(string context) {ShowPredictions(context,"");}
        void ShowPredictions(string context,string prefix) {candidates=engine.Predict(context,prefix);DrawCandidates();}
        void DrawCandidates() {
            candidatePanel.Children.Clear();
            if(candidates.Count==0) {
                var empty=Text("当前编码没有匹配字，请退格或按回车清空编码。",15,Muted,FontWeights.Normal);empty.Margin=new Thickness(12,16,12,16);candidatePanel.Children.Add(empty);
                foreach(var key in keys.Values){key.BorderBrush=BrushOf("#DDE4DE");key.BorderThickness=new Thickness(1);key.Background=Brushes.White;}
                detailText.Text="暂无匹配候选。";return;
            }
            for(int i=0;i<candidates.Count;i++) {
                var item=candidates[i];var grid=new Grid {Margin=new Thickness(12,4,12,4)};
                foreach(double w in new[]{58.0,70,115,125,315,230})grid.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(w)});
                var parts=new[]{Text((i+1).ToString("00"),12,Muted,FontWeights.Normal),Text(item.Info.Character,25,Ink,FontWeights.SemiBold),Text(item.Info.Code,17,Accent,FontWeights.Bold),Text(string.IsNullOrEmpty(item.Info.ShortCode)?"—":item.Info.ShortCode,12,Muted,FontWeights.Normal),item.Info.Units.Length==0?Text("暂无拆分资料",12,Muted,FontWeights.Normal):RootText(item.Info.Units,25),Text(item.Reason,12,Muted,FontWeights.Normal)};
                for(int k=0;k<parts.Length;k++) {parts[k].VerticalAlignment=VerticalAlignment.Center;Grid.SetColumn(parts[k],k);grid.Children.Add(parts[k]);}
                var row=new Border {Child=grid,CornerRadius=new CornerRadius(8),Background=Brushes.White,Margin=new Thickness(0,2,0,2),Cursor=Cursors.Hand,ToolTip=item.Info.Explanation};
                row.MouseLeftButtonUp+=delegate {Select(item);};candidatePanel.Children.Add(row);
            }
            if(candidates.Count>0)Select(candidates[0]);
        }
        void Select(Candidate candidate) {
            selectedCode=candidate.Info.Code;
            foreach(var pair in keys) {bool selected=selectedCode.Contains(pair.Key);pair.Value.BorderBrush=selected?Accent:BrushOf("#DDE4DE");pair.Value.BorderThickness=new Thickness(selected?2:1);pair.Value.Background=selected?BrushOf("#DEF1E7"):Brushes.White;}
            detailText.Text=candidate.Info.Character+"   "+string.Join(" → ",selectedCode.Select(c=>c.ToString()).ToArray())+"     "+candidate.Info.Explanation;
            for(int i=0;i<candidatePanel.Children.Count;i++) ((Border)candidatePanel.Children[i]).Background=candidates[i]==candidate?BrushOf("#EAF3EE"):Brushes.White;
        }
        void MakeRootKeys() {
            var counts=new Dictionary<char,Dictionary<char,int>>();
            foreach(var info in engine.Characters.Values) {
                var units=info.Units;
                if(units.Length==0)continue;
                int length=Math.Min(units.Length,info.Code.Length);
                if(info.Identification) length--;
                if(info.CharUnit||info.KeyUnit)length=1;
                for(int i=0;i<length;i++) {
                    char key=info.Code[i],unit=units[i];
                    if(!counts.ContainsKey(key))counts[key]=new Dictionary<char,int>();
                    if(!counts[key].ContainsKey(unit))counts[key][unit]=0;counts[key][unit]++;
                }
            }
            foreach(var pair in counts) rootKeys[pair.Key]=new string(pair.Value.OrderByDescending(p=>p.Value).Select(p=>p.Key).ToArray());
        }
        Border Key(char c) {
            var panel=new StackPanel();
            var head=new DockPanel();var letter=Text(c.ToString(),17,Zone(c),FontWeights.Bold);head.Children.Add(letter);
            string bases="工子又大月土王目水日口田山已火之金白木禾立女人幺言";
            int idx="ABCDEFGHIJKLMNOPQRSTUVWXYZ".IndexOf(c);
            var baseText=Text(c=='Z'?"学习键":(idx>=0&&idx<25?bases[idx].ToString():""),11,Muted,FontWeights.Normal);baseText.HorizontalAlignment=HorizontalAlignment.Right;head.Children.Add(baseText);panel.Children.Add(head);
            string roots;rootKeys.TryGetValue(c,out roots);roots=roots??"";
            var rootLabel=RootText(roots,14);rootLabel.TextWrapping=TextWrapping.Wrap;rootLabel.LineHeight=16;rootLabel.Margin=new Thickness(0,4,0,0);panel.Children.Add(rootLabel);
            if(c=='Z')panel.Children.Add(Text("万能查询",12,Muted,FontWeights.Normal));
            var box=new Border {Width=90,Height=102,Padding=new Thickness(7,4,7,4),Margin=new Thickness(3),Background=Brushes.White,BorderBrush=BrushOf("#DDE4DE"),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(8),Child=panel,ToolTip=Mnemonic(c)};
            keys[c]=box;return box;
        }
        static Brush Zone(char c) {string s=c.ToString();return BrushOf("GFDSA".Contains(s)?"#AD682E":"HJKLM".Contains(s)?"#357C99":"TREWQ".Contains(s)?"#458159":"YUIOP".Contains(s)?"#8B6699":"#AC6470");}
        static string Mnemonic(char c) {
            string[] sayings={"工戈草头右框七","子耳了也框向上","又巴马，丢矢矣","大犬三羊古石厂","月彡乃用家衣底","土士二干十寸雨","王旁青头戋五一","目具上止卜虎皮","水旁兴头小倒立","日早两竖与虫依","口与川，字根稀","田甲方框四车力","山由贝，下框几","已半巳满不出己，左框折尸心和羽","火业头，四点米","之字军盖建道底","金勺缺点无尾鱼，犬旁留儿一点夕","白手看头三二斤","木丁西","禾竹一撇双人立，反文条头共三一","立辛两点六门疒","女刀九臼山朝西","人和八，三四里","慈母无心弓和匕，幼无力","言文方广在四一，高头一捺谁人去","Z：学习键（依输入法而异）"};
            return sayings[c-'A'];
        }
        TextBlock RootText(string text,double size) {return new TextBlock {Text=text,FontFamily=rootFont,FontSize=size,Foreground=Ink};}
        static TextBlock Text(string text,double size,Brush color,FontWeight weight) {return new TextBlock {Text=text,FontSize=size,Foreground=color,FontWeight=weight};}
        static Button ActionButton(string text,Action action) {
            var b=new Button {Content=text,Focusable=false,Padding=new Thickness(11,7,11,7),Margin=new Thickness(5,0,0,0),Background=Brushes.White,Foreground=Ink,BorderBrush=BrushOf("#D5DDD7"),Cursor=Cursors.Hand,FontSize=12};
            b.Click+=delegate {action();};return b;
        }
        void OpenManual() {
            bool wasPaused=paused; if(capture!=null)capture.Paused=true;
            var dialog=new Window {Title="手动上下文 / 查字",Width=540,Height=395,WindowStartupLocation=WindowStartupLocation.CenterOwner,Owner=this,Topmost=Topmost,Background=Background,FontFamily=FontFamily};
            var panel=new StackPanel {Margin=new Thickness(20)};
            panel.Children.Add(Text("输入一段上下文来预测，或输入一个汉字查看拆分。",14,Ink,FontWeights.Normal));
            var input=new TextBox {Text=lastContext,Height=115,TextWrapping=TextWrapping.Wrap,AcceptsReturn=true,FontSize=18,Margin=new Thickness(0,16,0,12),VerticalScrollBarVisibility=ScrollBarVisibility.Auto};panel.Children.Add(input);
            panel.Children.Add(Text("正在输入的五笔字母（可留空，例如 r / ru）",12,Muted,FontWeights.Normal));
            var prefixInput=new TextBox {Text=lastPrefix,MaxLength=4,FontSize=17,Margin=new Thickness(0,6,0,12)};panel.Children.Add(prefixInput);
            var buttons=new StackPanel {Orientation=Orientation.Horizontal};
            buttons.Children.Add(ActionButton("预测下一字",delegate {manual=true;paused=true;lastContext=LearningEngine.Limit(input.Text,80);lastPrefix=CompositionSnapshot.NormalizeCode(prefixInput.Text);lastComposition=prefixInput.Text.Trim();UpdateContextDisplay();sourceText.Text="手动上下文 · 点击继续恢复实时读取";ShowPredictions(lastContext,codeEnabled?lastPrefix:"");liveButton.Content="▶ 继续";dialog.Close();}));
            buttons.Children.Add(ActionButton("查单字",delegate {
                CharacterInfo info;if(!engine.Characters.TryGetValue(input.Text.Trim(),out info)) {MessageBox.Show(dialog,"请输入一个已收录的汉字。","查字");return;}
                manual=true;paused=true;lastContext="";lastPrefix="";lastComposition="";contextText.Text=input.Text.Trim();sourceText.Text="单字查询 · 点击继续恢复实时读取";candidates=new List<Candidate>{new Candidate{Info=info,Reason="单字查询"}};DrawCandidates();liveButton.Content="▶ 继续";dialog.Close();
            }));panel.Children.Add(buttons);dialog.Content=panel;dialog.Loaded+=delegate {input.Focus();input.SelectAll();};dialog.ShowDialog();
            if(capture!=null)capture.Paused=manual||paused||wasPaused;
        }
        void ShowHelp() {
            MessageBox.Show("默认显示候选。按住 F8 切换为字根键盘并隐藏候选，松开恢复；窗口尺寸不变。\n\n读取其他窗口光标前最多 80 字，并监听尚未提交的字母（最多 4 位）。\n\n例如上屏「直」后按 R，会结合「直 + R」预测「接」，显示 RUVG 和取码字根。继续输入、退格会更新；回车、空格、数字选词、Esc 和导航键会清空编码。四码后继续输入按新字处理。\n\n输入法开放 UIA / IMM 预编辑时，优先使用真实组合串；否则界面标注「按键推测」。按键推测无法完全还原自定义自动上屏、鼠标选词、输入法内部状态。使用拼音或英文时可关闭「编码提示」。\n\n五笔 86 版；离线词库联想，最多 5 个候选。字根末位可能为识别码，下方会说明。\n\n密码框不参与预测；不保存输入历史，不上传。暂停即停用监听并清空上下文与待输入编码。\n\n目标软件需开放辅助功能文本接口，否则使用手动上下文。\n\nCtrl+Alt+W 暂停 / 继续\nCtrl+Alt+T 切换置顶\n\n数据来源见 THIRD-PARTY.md。","五笔伴学 · 使用说明",MessageBoxButton.OK,MessageBoxImage.Information);
        }
        public void Demo(string context) {sourceText.Text="预览 · 手动上下文";contextText.Text=context;ShowPredictions(context);}
        public void Demo(string context,string prefix) {sourceText.Text="预览 · 按键推测";lastContext=context;lastPrefix=prefix;lastComposition=prefix;UpdateContextDisplay();ShowPredictions(context,prefix);}
    }
}
