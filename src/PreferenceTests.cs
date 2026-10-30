using System;
using System.IO;
using System.Linq;
using System.Text;

namespace WubiCoach {
    internal static class PreferenceTests {
        static void Check(bool value,string message,StringBuilder log) {
            if(!value)throw new Exception("Preference regression: "+message);
            log.AppendLine("PASS: "+message);
        }
        public static void Run(LearningEngine engine,StringBuilder log) {
            string directory=Path.Combine(Path.GetTempPath(),"wubi-preferences-"+Guid.NewGuid());Directory.CreateDirectory(directory);
            try {
                string path=Path.Combine(directory,"counts.sqlite3");
                using(var store=new PreferenceStore(path)) {
                    store.Record("不保存这整段输入你好","猫",1);store.Record("你好","猫",1);store.Record("你好","吗",1);
                    Check(store.Scores("")["猫"]==2.0/3.0,"SQLite exact accumulated counts",log);
                    Check(string.Join(",",PreferenceStore.Contexts("private@example.com，输入你好"))==",好,你好,入你好","only three preceding Han characters retained",log);
                    Check(PreferenceStore.Contexts("中文abc").SequenceEqual(new[]{""}),"Latin context is not persisted",log);
                }
                using(var reopened=new PreferenceStore(path))Check(reopened.Scores("你好")["猫"]>reopened.Scores("你好")["吗"],"SQLite preferences survive reopening",log);
                using(var predictor=new PersonalizedPredictor(engine,Path.Combine(directory,"personal.sqlite3"))) {
                    var baseline=engine.Predict("直");var cold=predictor.Predict("直","");
                    Check(cold.All.Select(p=>p.Info.Character).SequenceEqual(baseline.Select(p=>p.Info.Character)),"cold start preserves baseline order",log);
                    predictor.Record("直","猫",true);predictor.Record("你好","吗",true);
                    foreach(var query in new[]{new[]{"直",""},new[]{"你好",""},new[]{"直","R"},new[]{"直","YYYY"},new[]{"直","VVVV"},new[]{"直","Q"}}) {
                        var columns=predictor.Predict(query[0],query[1]);var left=columns.Preferred.Select(p=>p.Info.Character).ToList();
                        Check(columns.Preferred.Count<=9&&columns.Regular.Count<=9,"two columns bounded to nine "+query[1],log);
                        Check(columns.All.Select(p=>p.Info.Character).Distinct().Count()==columns.All.Count,"no cross-column duplicates "+query[1],log);
                        Check(columns.Regular.Select(p=>p.Info.Character).SequenceEqual(engine.Predict(query[0],query[1]).Where(p=>!left.Contains(p.Info.Character)).Take(9).Select(p=>p.Info.Character)),"right column is baseline minus left "+query[1],log);
                        Check(columns.All.All(p=>query[1].Length==0||p.Info.Code.StartsWith(query[1],StringComparison.Ordinal)||p.Info.ShortCode.Split(' ').Any(c=>c.StartsWith(query[1],StringComparison.Ordinal))),"all personal predictions obey code filter "+query[1],log);
                    }
                    Check(predictor.Predict("直","").Preferred[0].Info.Character=="猫","personal next character outranks baseline",log);
                    Check(predictor.Predict("你好","").Preferred[0].Info.Character=="吗","context-specific preference",log);
                    Check(predictor.Notice.Length==0,"preferences recorded without errors",log);
                }
                string broken=Path.Combine(directory,"broken.sqlite3");File.WriteAllText(broken,"broken database");
                using(var predictor=new PersonalizedPredictor(engine,broken)) {
                    Check(predictor.Notice.Length>0,"database failure is visible",log);
                    Check(predictor.Predict("直","").All.Select(p=>p.Info.Character).SequenceEqual(engine.Predict("直").Select(p=>p.Info.Character)),"broken database safely falls back",log);
                    Check(File.ReadAllText(broken)=="broken database","broken database is not overwritten",log);
                }
                var tracker=new CommittedInputTracker();
                Check(tracker.Observe("你好","","A").Count==0&&tracker.Observe("你好","Q","A").Count==0,"initial text and preedit are not learned",log);
                var committed=tracker.Observe("你好猫","","A");
                Check(committed.Count==1&&committed[0].Key=="你好"&&committed[0].Value=="猫","confirmed composition append learned once",log);
                Check(tracker.Observe("你好猫","","A").Count==0,"repeated polling does not learn twice",log);
                Check(tracker.Observe("你好猫咪","Q","B").Count==0,"focus switch does not learn",log);
                Check(tracker.Observe("你好猫","Q","B").Count==0&&tracker.Observe("你好","","B").Count==0,"deletion does not learn",log);
                tracker.Observe("你好","Q","B");tracker.Clear();
                Check(tracker.Observe("你好猫","","B").Count==0,"pause/manual reset stops learning",log);
                tracker.Observe("你","Q","A");Check(tracker.Observe("你好很长的一段粘贴文本","","A").Count==0,"long paste does not learn",log);
                string old=new string('你',79)+"好";tracker.Observe(old,"Q","C");
                Check(tracker.Observe(old.Substring(1)+"猫","","C").Single().Value=="猫","80-character sliding context learns append",log);
            }finally {Directory.Delete(directory,true);}
        }
    }
}
