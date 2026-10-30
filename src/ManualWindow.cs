using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace WubiCoach {
    // Mirrors the macOS manual window: Roman pinyin, all single characters,
    // a Wubi preview, and the existing context/direct-character lookup tab.
    public sealed class ManualWindow : Window {
        readonly LearningEngine engine;
        readonly FontFamily rootFont;
        readonly Func<string,string,bool,bool> apply;
        readonly TextBox query=new TextBox {FontSize=18,Padding=new Thickness(6),MaxLength=32};
        readonly TextBlock resultMessage=Label("",12);
        readonly ListBox results=new ListBox {BorderThickness=new Thickness(0),Background=Brushes.Transparent};
        readonly StackPanel detail=new StackPanel();
        readonly Button viewButton=new Button {Content="查看五笔",IsEnabled=false,Padding=new Thickness(12,6,12,6)};
        static readonly Brush Accent=MainWindow.BrushOf("#007D72"),Muted=MainWindow.BrushOf("#697B78");
        public ManualWindow(LearningEngine model,FontFamily radicals,string context,string prefix,Func<string,string,bool,bool> applyManual) {
            engine=model;rootFont=radicals;apply=applyManual;
            Title="手动上下文 / 查字";Width=620;Height=590;ResizeMode=ResizeMode.NoResize;
            Background=MainWindow.BrushOf("#F3F5F0");Foreground=MainWindow.BrushOf("#1E3432");
            WindowStartupLocation=WindowStartupLocation.CenterOwner;
            var panel=new DockPanel {Margin=new Thickness(20)};
            var heading=new StackPanel();heading.Children.Add(Label("手动 / 查字",21));
            var subtitle=Label("内置离线拼音 · 只查单字，不需要切换系统输入法",13);subtitle.Foreground=Muted;subtitle.Margin=new Thickness(0,6,0,12);heading.Children.Add(subtitle);
            DockPanel.SetDock(heading,Dock.Top);panel.Children.Add(heading);
            var hint=Label("返回其他应用后自动继续读取；原本已暂停时保持暂停。",12);hint.Foreground=Muted;hint.Margin=new Thickness(0,10,0,0);
            DockPanel.SetDock(hint,Dock.Bottom);panel.Children.Add(hint);
            var tabs=new TabControl();
            tabs.Items.Add(new TabItem {Header="拼音查字",Content=BuildPinyin()});
            tabs.Items.Add(new TabItem {Header="上下文 / 汉字查码",Content=BuildContext(context,prefix)});
            panel.Children.Add(tabs);Content=panel;
            InputMethod.SetIsInputMethodEnabled(query,false);
            InputMethod.SetIsInputMethodSuspended(query,true);
            query.TextChanged+=delegate {Search();};
            query.PreviewKeyDown+=delegate(object sender,KeyEventArgs e) {if(e.Key==Key.Enter){ApplySelection();e.Handled=true;}else if(e.Key==Key.Down&&results.Items.Count>0){results.Focus();results.SelectedIndex=Math.Min(results.Items.Count-1,results.SelectedIndex+1);e.Handled=true;}};
            results.SelectionChanged+=delegate {ShowDetail();};
            results.MouseDoubleClick+=delegate {ApplySelection();};
            results.PreviewKeyDown+=delegate(object sender,KeyEventArgs e) {if(e.Key==Key.Enter){ApplySelection();e.Handled=true;}};
            viewButton.Click+=delegate {ApplySelection();};
            Loaded+=delegate {query.Focus();};Search();
        }
        UIElement BuildPinyin() {
            var panel=new DockPanel {Margin=new Thickness(12)};
            var input=new StackPanel();input.Children.Add(query);resultMessage.Margin=new Thickness(0,8,0,10);resultMessage.TextWrapping=TextWrapping.Wrap;input.Children.Add(resultMessage);
            DockPanel.SetDock(input,Dock.Top);panel.Children.Add(input);
            var bottom=new StackPanel();
            bottom.Children.Add(new Border {Child=detail,MinHeight=100,Background=MainWindow.BrushOf("#E2EEEA"),CornerRadius=new CornerRadius(8),Padding=new Thickness(10),Margin=new Thickness(0,8,0,10)});
            var actions=new DockPanel();
            var buttons=new StackPanel {Orientation=Orientation.Horizontal};buttons.Children.Add(viewButton);buttons.Children.Add(CloseButton());DockPanel.SetDock(buttons,Dock.Right);actions.Children.Add(buttons);
            var note=Label("不分声调 · ü 用 v · 完整拼音匹配",11);note.Foreground=Muted;note.VerticalAlignment=VerticalAlignment.Center;actions.Children.Add(note);bottom.Children.Add(actions);
            DockPanel.SetDock(bottom,Dock.Bottom);panel.Children.Add(bottom);
            results.SetValue(ScrollViewer.HorizontalScrollBarVisibilityProperty,ScrollBarVisibility.Disabled);
            results.SetValue(ScrollViewer.VerticalScrollBarVisibilityProperty,ScrollBarVisibility.Auto);
            var factory=new FrameworkElementFactory(typeof(WrapPanel));
            results.ItemsPanel=new ItemsPanelTemplate(factory);
            var style=new Style(typeof(ListBoxItem));style.Setters.Add(new Setter(Control.PaddingProperty,new Thickness(0)));style.Setters.Add(new Setter(FrameworkElement.MarginProperty,new Thickness(2)));style.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty,HorizontalAlignment.Center));
            results.ItemContainerStyle=style;
            panel.Children.Add(results);return panel;
        }
        void Search() {
            var found=engine.Pinyin.Search(query.Text);results.Items.Clear();
            foreach(var item in found) {
                var label=Label(item.Character,27);label.Width=46;label.Height=38;label.TextAlignment=TextAlignment.Center;
                label.ToolTip=string.Join(" / ",item.Readings);label.Tag=item;results.Items.Add(label);
            }
            resultMessage.Text=query.Text.Trim().Length==0?"输入一个完整拼音，显示全部同音单字；点击汉字预览，回车查看五笔。":found.Count==0?"暂无匹配单字，请输入一个完整拼音（例如 ni，不是 nihao）。":PinyinIndex.Normalize(query.Text)+" · 共 "+found.Count+" 个单字 · 常用字优先，可滚动查看全部";
            results.SelectedIndex=found.Count==0?-1:0;
            if(found.Count>0)results.ScrollIntoView(results.Items[0]);
            ShowDetail();
        }
        PinyinCharacter Selected {get {var label=results.SelectedItem as TextBlock;return label==null?null:label.Tag as PinyinCharacter;}}
        void ShowDetail() {
            detail.Children.Clear();var item=Selected;viewButton.IsEnabled=false;
            if(item==null){detail.Children.Add(Label("选择一个汉字，查看五笔完整码、简码和字根。",13));return;}
            var row=new WrapPanel {VerticalAlignment=VerticalAlignment.Center};
            row.Children.Add(Label(item.Character,30));
            var reading=Label("  "+string.Join(" / ",item.Readings)+"  ",14);reading.Foreground=Muted;reading.VerticalAlignment=VerticalAlignment.Center;row.Children.Add(reading);
            CharacterInfo info;
            if(engine.Characters.TryGetValue(item.Character,out info)) {
                var code=Label(info.Code,19);code.Foreground=Accent;code.FontWeight=FontWeights.Bold;row.Children.Add(code);
                row.Children.Add(Label("  简码 "+(info.ShortCode.Length==0?"—":info.ShortCode)+"  ",12));
                string units=info.Units.Length==0?"暂无拆分资料":info.Identification?info.Units.Substring(0,info.Units.Length-1):info.Units;
                row.Children.Add(new TextBlock {Text=units,FontFamily=info.Units.Length==0?FontFamily:rootFont,FontSize=25});
                if(info.Identification) {var identification=Label("  识别码 "+info.Code.Substring(info.Code.Length-1),12);identification.Foreground=Accent;row.Children.Add(identification);}
                viewButton.IsEnabled=true;
            }
            detail.Children.Add(row);
            var explanation=Label(info==null?"当前五笔词库未收录此字；仍保留在拼音结果中。":info.Explanation,12);explanation.TextWrapping=TextWrapping.Wrap;explanation.Margin=new Thickness(0,6,0,0);detail.Children.Add(explanation);
        }
        void ApplySelection() {var item=Selected;if(item!=null&&engine.Characters.ContainsKey(item.Character)&&apply(item.Character,"",true))Close();}
        UIElement BuildContext(string context,string prefix) {
            var panel=new DockPanel {Margin=new Thickness(12)};
            var description=Label("输入上下文来预测，或输入一个汉字查询拆分。",13);description.Margin=new Thickness(0,0,0,12);DockPanel.SetDock(description,Dock.Top);panel.Children.Add(description);
            var input=new TextBox {Text=context,AcceptsReturn=true,TextWrapping=TextWrapping.Wrap,FontSize=18,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
            var bottom=new StackPanel {Margin=new Thickness(0,12,0,0)};
            bottom.Children.Add(Label("正在输入的五笔字母，例如 r / ru（可留空）",12));
            var code=new TextBox {Text=prefix,MaxLength=4,FontSize=17,Margin=new Thickness(0,6,0,12)};bottom.Children.Add(code);
            var buttons=new StackPanel {Orientation=Orientation.Horizontal};
            var predict=Button("预测下一字",delegate {if(apply(input.Text,code.Text,false))Close();});
            var lookup=Button("查单字",delegate {if(apply(input.Text,"",true))Close();else MessageBox.Show(this,"请输入一个已收录的汉字。","查字");});
            buttons.Children.Add(predict);buttons.Children.Add(lookup);buttons.Children.Add(CloseButton());bottom.Children.Add(buttons);
            DockPanel.SetDock(bottom,Dock.Bottom);panel.Children.Add(bottom);panel.Children.Add(input);return panel;
        }
        Button CloseButton() {var button=Button("关闭",delegate {Close();});button.IsCancel=true;return button;}
        static Button Button(string title,Action action) {var button=new Button {Content=title,Padding=new Thickness(10,6,10,6),Margin=new Thickness(6,0,0,0)};button.Click+=delegate {action();};return button;}
        static TextBlock Label(string text,double size) {return new TextBlock {Text=text,FontSize=size};}
    }
}
