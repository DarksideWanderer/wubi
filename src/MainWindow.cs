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
        readonly PersonalizedPredictor predictor;
        readonly CommittedInputTracker learning=new CommittedInputTracker();
        readonly TextBlock preferenceTitle;
        List<Candidate> preferredCandidates=new List<Candidate>(),regularCandidates=new List<Candidate>();
        bool singleLookup;
        DateTime lastLearningSample=DateTime.MinValue;
        readonly FontFamily rootFont;
        readonly Dictionary<char, Border> keys=new Dictionary<char,Border>();
        readonly Dictionary<char,string> rootKeys=new Dictionary<char,string>();
        readonly Grid candidatePanel=new Grid {Height=232};
        readonly List<Border> candidateRows=new List<Border>();
        readonly StackPanel candidateView=new StackPanel();
        readonly StackPanel keyboardPanel=new StackPanel {Visibility=Visibility.Collapsed};
        readonly TextBlock contextText, sourceText, detailText;
        readonly Button pinButton, liveButton,codeButton,helpButton;
        ContextCapture capture;
        bool paused, manualOpen, closing,codeEnabled=true,refreshAfterPreview;
        string lastContext="",lastStatus="", selectedCode="",lastPrefix="",lastComposition="";
        List<Candidate> candidates;
        IntPtr handle;
        static readonly Brush Ink=BrushOf("#1E3432"), Muted=BrushOf("#697B78"), Accent=BrushOf("#007D72");
        public UIElement Artboard {get;private set;}
        public static Brush BrushOf(string s) { return (Brush)new BrushConverter().ConvertFromString(s); }
        public MainWindow(LearningEngine model,string dataDirectory,bool preview) {
            engine=model;
            predictor=new PersonalizedPredictor(engine,preview?null:
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"WubiCoach","preferences.sqlite3"));
            rootFont=Fonts.GetFontFamilies(new Uri(Path.GetFullPath(dataDirectory)+Path.DirectorySeparatorChar)).FirstOrDefault() ?? new FontFamily("Microsoft YaHei UI");
            MakeRootKeys();
            foreach(var line in File.ReadLines(Path.Combine(dataDirectory,"keyboard.tsv"),Encoding.UTF8)) {
                var rootColumns=line.Split('\t');
                if(rootColumns.Length<4 || rootColumns[0].Length==0 || rootColumns[0][0]<'A' || rootColumns[0][0]>'Y')continue;
                rootKeys[rootColumns[0][0]]=string.Concat(Regex.Matches(string.Join("",rootColumns.Skip(1).Take(3).ToArray()),"[\uE000-\uF8FF]").Cast<Match>().Select(m=>m.Value).Distinct().ToArray());
            }
            Title="五笔伴学 · 86版"; Width=816; Height=459; MinWidth=816;MinHeight=459;SizeToContent=SizeToContent.WidthAndHeight;
            Background=BrushOf("#F3F5F0"); FontFamily=new FontFamily("Microsoft YaHei UI"); Foreground=Ink;
            WindowStartupLocation=WindowStartupLocation.CenterScreen; Topmost=true;ShowActivated=false;
            var board=new StackPanel {Width=772,Margin=new Thickness(14,10,14,10)};
            var header=new DockPanel {Margin=new Thickness(0,0,0,8)};
            var actions=new StackPanel {Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center};
            pinButton=ActionButton("● 已置顶",delegate {Topmost=!Topmost;pinButton.Content=Topmost?"● 已置顶":"○ 置顶";});
            liveButton=ActionButton("Ⅱ 暂停",delegate {ToggleLive();});
            actions.Children.Add(pinButton); actions.Children.Add(liveButton);
            codeButton=ActionButton("编码：开",delegate {codeEnabled=!codeEnabled;codeButton.Content=codeEnabled?"编码：开":"编码：关";ShowPredictions(lastContext,codeEnabled?lastPrefix:"");});
            actions.Children.Add(codeButton);
            actions.Children.Add(ActionButton("手动 / 查字",delegate {OpenManual();}));
            helpButton=ActionButton("帮助",delegate {ShowHelp();});actions.Children.Add(helpButton);
            DockPanel.SetDock(actions,Dock.Right);header.Children.Add(actions);
            var brand=new StackPanel();brand.Children.Add(Text("五笔伴学",21,Ink,FontWeights.Bold));
            brand.Children.Add(Text("86 版 · 离线联想",11,Muted,FontWeights.Normal));
            header.Children.Add(brand);board.Children.Add(header);
            var contentSlot=new Grid {Height=328};
            keyboardPanel.VerticalAlignment=VerticalAlignment.Center;
            contentSlot.Children.Add(candidateView);contentSlot.Children.Add(keyboardPanel);board.Children.Add(contentSlot);
            var contextBox=new Border {Background=BrushOf("#E4EEEA"),CornerRadius=new CornerRadius(12),Padding=new Thickness(6),Margin=new Thickness(0,0,0,4)};
            var contextStack=new StackPanel();sourceText=Text("等待其他窗口的输入框 · 光标前最多 80 字",10,Accent,FontWeights.SemiBold);
            contextText=Text("在其他窗口输入中文，输入法上屏后会在这里显示上下文。",13,Ink,FontWeights.Normal);contextText.Margin=new Thickness(0,3,0,0);contextText.TextTrimming=TextTrimming.CharacterEllipsis;
            contextStack.Children.Add(sourceText);contextStack.Children.Add(contextText);contextBox.Child=contextStack;candidateView.Children.Add(contextBox);
            var labelRow=new Grid {Margin=new Thickness(3,0,3,4)};
            labelRow.ColumnDefinitions.Add(new ColumnDefinition());labelRow.ColumnDefinitions.Add(new ColumnDefinition());
            preferenceTitle=Text("个人偏好 · 不足时按常规补齐",11,Ink,FontWeights.SemiBold);labelRow.Children.Add(preferenceTitle);
            var regularTitle=Text("常规联想 · 已排除左侧",11,Ink,FontWeights.SemiBold);Grid.SetColumn(regularTitle,1);regularTitle.Margin=new Thickness(6,0,0,0);labelRow.Children.Add(regularTitle);candidateView.Children.Add(labelRow);
            candidatePanel.ColumnDefinitions.Add(new ColumnDefinition());
            candidatePanel.ColumnDefinitions.Add(new ColumnDefinition());
            candidateView.Children.Add(candidatePanel);
            var detailBox=new Border {CornerRadius=new CornerRadius(9),Background=BrushOf("#D9EAE2"),Padding=new Thickness(6),Margin=new Thickness(0,4,0,0)};
            detailText=Text("选择一个候选，查看取码规则。",11,Ink,FontWeights.Normal);detailText.TextTrimming=TextTrimming.CharacterEllipsis;detailBox.Child=detailText;candidateView.Children.Add(detailBox);
            var keyboardTitle=new DockPanel {Margin=new Thickness(3,0,3,5)};
            var legend=new StackPanel {Orientation=Orientation.Horizontal};
            foreach(var pair in new[]{"横区 · GFDSA","竖区 · HJKLM","撇区 · TREWQ","捺区 · YUIOP","折区 · NBVCX"}) {
                char letter=pair[pair.Length-1];var t=Text(pair,10,Zone(letter),FontWeights.SemiBold);t.Margin=new Thickness(14,0,0,0);legend.Children.Add(t);
            }
            DockPanel.SetDock(legend,Dock.Right);keyboardTitle.Children.Add(legend);keyboardTitle.Children.Add(Text("字根键盘 · 基本字根",12,Ink,FontWeights.Bold));keyboardPanel.Children.Add(keyboardTitle);
            foreach(var row in new[]{"QWERTYUIOP","ASDFGHJKL","ZXCVBNM"}) {
                var rowPanel=new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Center};
                foreach(char c in row) rowPanel.Children.Add(Key(c));keyboardPanel.Children.Add(rowPanel);
            }
            Artboard=new Border {Width=800,Height=420,Background=Background,Child=board};
            Content=Artboard;
            ShowPredictions("");
            SourceInitialized+=delegate {
                handle=new WindowInteropHelper(this).Handle;
                Native.SetWindowLong(handle,-20,Native.GetWindowLong(handle,-20)|0x08000000);
                HwndSource.FromHwnd(handle).AddHook(WindowHook);
                bool a=Native.RegisterHotKey(handle,1,0x4003,0x57),b=Native.RegisterHotKey(handle,2,0x4003,0x54);
                if(!a||!b) helpButton.ToolTip="部分快捷键已被其他程序占用；可使用窗口上的按钮。";
            };
            if(!preview) Loaded+=delegate {capture=new ContextCapture();capture.Updated+=OnSnapshot;capture.KeyboardVisibilityChanged+=SetKeyboardVisible;if(!capture.KeyboardAvailable)helpButton.ToolTip="按键监听未能启动；Ctrl+Alt+K 暂不可用，仍会尝试读取输入法预编辑。";};
            Closed+=delegate {closing=true;if(capture!=null)capture.Dispose();predictor.Dispose();Native.UnregisterHotKey(handle,1);Native.UnregisterHotKey(handle,2);};
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
            paused=!paused;
            learning.Clear();
            if(capture!=null)capture.Paused=paused||manualOpen;
            liveButton.Content=paused?"▶ 继续":"Ⅱ 暂停";
            if(paused) {ClearContext("已暂停读取 · 上下文已清除");} else {lastContext="\0";sourceText.Text="等待其他窗口的输入框";}
        }
        void OnSnapshot(ContextSnapshot snapshot) {
            if(closing || snapshot.Ignore)return;
            Dispatcher.BeginInvoke(new Action(delegate {
                if(closing || paused || manualOpen)return;
                if(!snapshot.Available) {if(lastStatus!=snapshot.Status)ClearContext(snapshot.Source+" · "+snapshot.Status);lastStatus=snapshot.Status;return;}
                lastStatus="";sourceText.Text=snapshot.Source+" · "+snapshot.Status+" · "+(snapshot.Composition.Text.Length>0?snapshot.Composition.Source:"按键监听");
                string prefix=snapshot.Composition.CodePrefix;
                if((DateTime.UtcNow-lastLearningSample).TotalSeconds>1)learning.Clear();
                lastLearningSample=DateTime.UtcNow;
                foreach(var observation in learning.Observe(snapshot.Text,prefix,snapshot.Window.ToString()+":"+snapshot.ControlIdentity))
                    predictor.Record(observation.Key,observation.Value,false);
                if(!refreshAfterPreview && lastContext==snapshot.Text && lastPrefix==prefix && lastComposition==snapshot.Composition.Text)return;
                refreshAfterPreview=false;
                lastContext=snapshot.Text;lastPrefix=prefix;lastComposition=snapshot.Composition.Text;
                UpdateContextDisplay();ShowPredictions(lastContext,codeEnabled?lastPrefix:"");
            }));
        }
        void UpdateContextDisplay() {
            contextText.Text=(lastContext.Length==0?"光标前暂无文字。":lastContext.Replace("\n"," ↵ "))+
                (lastComposition.Length>0?"    │    正在输入："+lastComposition+(lastPrefix.Length==0?"（非五笔码，不筛选）":""):"");
        }
        void ClearContext(string status) {learning.Clear();lastContext="";lastPrefix="";lastComposition="";contextText.Text="—";sourceText.Text=status;ShowPredictions("");}
        void ShowPredictions(string context) {ShowPredictions(context,"");}
        void ShowPredictions(string context,string prefix) {
            singleLookup=false;var columns=predictor.Predict(context,prefix);
            preferredCandidates=columns.Preferred;regularCandidates=columns.Regular;candidates=columns.All;
            preferenceTitle.Text=predictor.Notice.Length==0?"个人偏好 · 不足时按常规补齐":"偏好不可用 · 常规补齐";
            preferenceTitle.ToolTip=predictor.Notice.Length==0?"点击候选与确认上屏的新字会保存在本机，作为个人偏好。":predictor.Notice;
            DrawCandidates();
        }
        Grid CandidateColumns() {
            var grid=new Grid();
            foreach(double width in new[]{24.0,30,56,70})grid.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(width)});
            grid.ColumnDefinitions.Add(new ColumnDefinition());return grid;
        }
        void DrawCandidates() {
            candidatePanel.Children.Clear();candidateRows.Clear();
            if(candidates.Count==0) {
                var empty=Text("当前编码没有匹配字，请退格或按回车清空编码。",13,Muted,FontWeights.Normal);
                empty.Margin=new Thickness(6,12,6,12);Grid.SetColumnSpan(empty,2);candidatePanel.Children.Add(empty);
                foreach(var key in keys.Values){key.BorderBrush=BrushOf("#DDE4DE");key.BorderThickness=new Thickness(1);key.Background=Brushes.White;}
                detailText.Text="暂无匹配候选。";return;
            }
            for(int column=0;column<2;column++) {
                var items=column==0?preferredCandidates:regularCandidates;
                var panel=new StackPanel {Margin=column==0?new Thickness(0,0,6,0):new Thickness(6,0,0,0)};
                Grid.SetColumn(panel,column);candidatePanel.Children.Add(panel);
                var header=CandidateColumns();header.Height=14;header.Margin=new Thickness(4,0,4,4);
                string[] labels={"序","字","完整码","简码","取码字根 / 识别码"};
                for(int k=0;k<labels.Length;k++){var text=Text(labels[k],10,Muted,FontWeights.Normal);Grid.SetColumn(text,k);header.Children.Add(text);}panel.Children.Add(header);
                for(int offset=0;offset<9;offset++) {
                    int i=column*9+offset;
                    if(offset>=items.Count)continue;
                    var item=items[offset];var grid=CandidateColumns();grid.Margin=new Thickness(4,0,4,0);
                    var parts=new[]{Text((i+1).ToString("00"),10,Muted,FontWeights.Normal),Text(item.Info.Character,19,Ink,FontWeights.SemiBold),Text(item.Info.Code,12,Accent,FontWeights.Bold),Text(string.IsNullOrEmpty(item.Info.ShortCode)?"—":item.Info.ShortCode,10,Muted,FontWeights.Normal),item.Info.Units.Length==0?Text("暂无拆分",10,Muted,FontWeights.Normal):RootText(item.Info.Units,18)};
                    for(int k=0;k<parts.Length;k++){parts[k].VerticalAlignment=VerticalAlignment.Center;parts[k].TextTrimming=TextTrimming.CharacterEllipsis;Grid.SetColumn(parts[k],k);grid.Children.Add(parts[k]);}
                    var row=new Border {Height=22,Child=grid,CornerRadius=new CornerRadius(5),Background=Brushes.White,Margin=new Thickness(0,0,0,offset==8?0:2),Cursor=Cursors.Hand,ToolTip=item.Info.Explanation};
                    row.MouseLeftButtonUp+=delegate {
                        if(!singleLookup){predictor.Record(lastContext,item.Info.Character,true);ShowPredictions(lastContext,codeEnabled?lastPrefix:"");}
                        Select(item);
                    };panel.Children.Add(row);candidateRows.Add(row);
                }
            }
            Select(candidates[0]);
        }
        void Select(Candidate candidate) {
            selectedCode=candidate.Info.Code;
            foreach(var pair in keys) {bool selected=selectedCode.Contains(pair.Key);pair.Value.BorderBrush=selected?Accent:BrushOf("#DDE4DE");pair.Value.BorderThickness=new Thickness(selected?2:1);pair.Value.Background=selected?BrushOf("#DEF1E7"):Brushes.White;}
            detailText.Text=candidate.Info.Character+"   "+string.Join(" → ",selectedCode.Select(c=>c.ToString()).ToArray())+"     "+candidate.Info.Explanation;
            for(int i=0;i<candidateRows.Count;i++) candidateRows[i].Background=candidates[i].Info.Character==candidate.Info.Character?BrushOf("#EAF3EE"):Brushes.White;
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
            var head=new DockPanel();var letter=Text(c.ToString(),14,Zone(c),FontWeights.Bold);head.Children.Add(letter);
            string bases="工子又大月土王目水日口田山已火之金白木禾立女人幺言";
            int idx="ABCDEFGHIJKLMNOPQRSTUVWXYZ".IndexOf(c);
            var baseText=Text(c=='Z'?"学习键":(idx>=0&&idx<25?bases[idx].ToString():""),11,Muted,FontWeights.Normal);baseText.HorizontalAlignment=HorizontalAlignment.Right;head.Children.Add(baseText);panel.Children.Add(head);
            string roots;rootKeys.TryGetValue(c,out roots);roots=roots??"";
            var rootLabel=RootText(roots,12);rootLabel.TextWrapping=TextWrapping.Wrap;rootLabel.LineHeight=14;rootLabel.Margin=new Thickness(0,4,0,0);panel.Children.Add(rootLabel);
            if(c=='Z')panel.Children.Add(Text("万能查询",12,Muted,FontWeights.Normal));
            var box=new Border {Width=70,Height=88,Padding=new Thickness(6),Margin=new Thickness(2),Background=Brushes.White,BorderBrush=BrushOf("#DDE4DE"),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(8),Child=panel,ToolTip=Mnemonic(c)};
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
            var b=new Button {Content=text,Focusable=false,Padding=new Thickness(8,4,8,4),Margin=new Thickness(5,0,0,0),Background=Brushes.White,Foreground=Ink,BorderBrush=BrushOf("#D5DDD7"),Cursor=Cursors.Hand,FontSize=12};
            b.Click+=delegate {action();};return b;
        }
        void OpenManual() {
            learning.Clear();manualOpen=true;if(capture!=null)capture.Paused=true;
            try {
                var dialog=new ManualWindow(engine,rootFont,lastContext,lastPrefix,ApplyManual) {Owner=this,Topmost=Topmost,FontFamily=FontFamily};
                dialog.ShowDialog();
            } finally {manualOpen=false;if(capture!=null)capture.Paused=paused;}
        }
        bool ApplyManual(string context,string prefix,bool lookup) {
            CharacterInfo info=null;
            if(lookup&&!engine.Characters.TryGetValue(context.Trim(),out info))return false;
            refreshAfterPreview=true;
            lastContext=LearningEngine.Limit(context,80);lastPrefix=lookup?"":CompositionSnapshot.NormalizeCode(prefix);lastComposition=lastPrefix;
            UpdateContextDisplay();sourceText.Text=paused?"手动查询 · 自动读取已暂停":"手动查询 · 返回其他应用后自动继续读取";
            if(lookup) {singleLookup=true;preferredCandidates=new List<Candidate>{new Candidate {Info=info,Reason="单字查询"}};regularCandidates=new List<Candidate>();candidates=preferredCandidates;DrawCandidates();}
            else ShowPredictions(lastContext,codeEnabled?lastPrefix:"");
            return true;
        }
        void ShowHelp() {
            MessageBox.Show("默认显示候选。按住 Ctrl+Alt+K 切换为字根键盘并隐藏候选，松开恢复；窗口尺寸不变。\n\n读取其他窗口光标前最多 80 字，并监听尚未提交的字母（最多 4 位）。\n\n例如上屏「直」后按 R，会结合「直 + R」预测「接」，显示 RUVG 和取码字根。继续输入、退格会更新；回车、空格、数字选词、Esc 和导航键会清空编码。四码后继续输入按新字处理。\n\n输入法开放 UIA / IMM 预编辑时，优先使用真实组合串；否则界面标注「按键推测」。按键推测无法完全还原自定义自动上屏、鼠标选词、输入法内部状态。使用拼音或英文时可关闭「编码提示」。\n\n五笔 86 版；离线词库联想，最多 18 个候选；左 9 为个人偏好，不足时常规补齐；右 9 为常规联想排除左侧。点击候选和确认上屏会学习偏好，重启后保留。字根末位可能为识别码，下方会说明。\n\n密码框不参与预测；仅在本机 SQLite 保存最多三个前置汉字、下一字及次数，不保存完整输入历史，不上传。暂停即停用监听并清空上下文与待输入编码。\n\n目标软件需开放辅助功能文本接口，否则使用手动上下文。\n\nCtrl+Alt+W 暂停 / 继续\nCtrl+Alt+T 切换置顶\n\n数据来源见 THIRD-PARTY.md。","五笔伴学 · 使用说明",MessageBoxButton.OK,MessageBoxImage.Information);
        }
        public void Demo(string context) {sourceText.Text="预览 · 手动上下文";contextText.Text=context;ShowPredictions(context);}
        public void Demo(string context,string prefix) {sourceText.Text="预览 · 按键推测";lastContext=context;lastPrefix=prefix;lastComposition=prefix;UpdateContextDisplay();ShowPredictions(context,prefix);}
    }
}
