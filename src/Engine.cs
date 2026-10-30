using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace WubiCoach {
    public sealed class CharacterInfo {
        public string Character, Code, ShortCode, Units, IdentificationDescription;
        public bool KeyUnit, CharUnit, StrokeUnit, Identification;
        public string Explanation {
            get {
                if (KeyUnit) return "键名字：连打四次所在键";
                if (StrokeUnit) return "单笔画：所在键两次 + LL";
                if (CharUnit) return "成字字根：报户口 + 首笔 + 次笔 + 末笔（不足则省略）";
                return Identification ? "末位识别码："+IdentificationDescription+"（不是额外字根）" : "按字根顺序取码；超过四根取首、次、三、末";
            }
        }
    }
    public sealed class Candidate {
        public CharacterInfo Info;
        public string Reason;
    }
    public sealed class LearningEngine {
        public readonly Dictionary<string,CharacterInfo> Characters = new Dictionary<string,CharacterInfo>();
        readonly Dictionary<string, Dictionary<string,double>> transitions = new Dictionary<string, Dictionary<string,double>>();
        readonly Dictionary<string,double> frequencies = new Dictionary<string,double>();
        public readonly PinyinIndex Pinyin;
        public int PhraseCount { get; private set; }
        public LearningEngine(string directory) {
            foreach (var line in File.ReadLines(Path.Combine(directory,"decomposition.tsv"),Encoding.UTF8).Skip(1)) {
                var p=line.Split('\t');
                if(p.Length<9 || p[0].Length!=1 || !Regex.IsMatch(p[1],"^[a-y]{1,4}$")) continue;
                Characters[p[0]]=new CharacterInfo { Character=p[0], Code=p[1].ToUpperInvariant(), ShortCode=p[2].Replace('/', ' ').ToUpperInvariant(),
                    KeyUnit=p[4]=="1", StrokeUnit=p[5]=="1", CharUnit=p[6]=="1", Units=p[7].Replace("〖","").Replace("〗","").Replace("※",""), Identification=p[8].Length>0, IdentificationDescription=Regex.Replace(p[8],"〔.*?〕","") };
            }
            var seen = new HashSet<string>();
            foreach (var line in File.ReadLines(Path.Combine(directory,"wubi86.dict.yaml"),Encoding.UTF8)) {
                if(line.StartsWith("#")) continue;
                var p=line.Split('\t');
                if(p.Length<2 || !Regex.IsMatch(p[1],"^[a-y]{1,4}$") || !seen.Add(p[0])) continue;
                double weight=1, value;
                if(p.Length>2 && double.TryParse(p[2].TrimEnd('%'),out value)) weight=1+Math.Sqrt(Math.Max(0,value))/100.0;
                var word=p[0];
                if(!word.All(c=>Characters.ContainsKey(c.ToString()))) continue;
                if(word.Length==1) Add(frequencies,word,weight);
                else { Train(word,weight); PhraseCount++; }
            }
            foreach(var line in File.ReadAllLines(Path.Combine(directory,"corpus.txt"),Encoding.UTF8))
                foreach(Match m in Regex.Matches(line,"[\u4e00-\u9fff]+")) Train(m.Value,12);
            // Stable common-character prior when no suffix is found.
            string common="的了是在我有和你不这人们中大为上个国到说时要就出会可也对生能而子那得于着下自之年过发后作里用道行所然家种事成多天好学谢见气欢想今明去吃饭工作生活";
            for(int i=0;i<common.Length;i++) Add(frequencies,common[i].ToString(),100-i);
            Pinyin=new PinyinIndex(Path.Combine(directory,"pinyin.tsv"),frequencies,new HashSet<string>(Characters.Keys));
        }
        static void Add(Dictionary<string,double> d,string k,double v) { double old; d.TryGetValue(k,out old); d[k]=old+v; }
        void Train(string text,double weight) {
            for(int i=1;i<text.Length;i++) {
                string next=text[i].ToString();
                if(!Characters.ContainsKey(next)) continue;
                for(int n=1;n<=Math.Min(6,i);n++) {
                    string prefix=text.Substring(i-n,n);
                    Dictionary<string,double> bucket;
                    if(!transitions.TryGetValue(prefix,out bucket)) transitions[prefix]=bucket=new Dictionary<string,double>();
                    Add(bucket,next,weight);
                }
            }
        }
        public List<Candidate> Predict(string context) {return Predict(context,"");}
        public List<Candidate> Predict(string context,string codePrefix) {
            codePrefix=CompositionSnapshot.NormalizeCode(codePrefix);
            var scores=new Dictionary<string,double>();
            var reasons=new Dictionary<string,string>();
            for(int n=Math.Min(6,context.Length);n>=1;n--) {
                string suffix=context.Substring(context.Length-n);
                Dictionary<string,double> bucket;
                if(!transitions.TryGetValue(suffix,out bucket)) continue;
                double sum=bucket.Values.Sum();
                foreach(var item in bucket) {
                    Add(scores,item.Key,Math.Pow(12,n)*item.Value/sum);
                    if(!reasons.ContainsKey(item.Key)) reasons[item.Key]="续接「"+suffix+"」";
                }
            }
            foreach(var item in frequencies) if(Characters.ContainsKey(item.Key)) Add(scores,item.Key,item.Value*0.00001);
            if(codePrefix.Length>0) foreach(var info in Characters.Values) if(info.Code.StartsWith(codePrefix,StringComparison.Ordinal) && !scores.ContainsKey(info.Character))scores[info.Character]=0;
            return scores.Where(p=>codePrefix.Length==0||Characters[p.Key].Code.StartsWith(codePrefix,StringComparison.Ordinal)||Characters[p.Key].ShortCode.Split(' ').Any(c=>c.StartsWith(codePrefix,StringComparison.Ordinal)))
                .OrderByDescending(p=>p.Value).ThenBy(p=>p.Key,StringComparer.Ordinal).Take(18)
                .Select(p=>new Candidate {Info=Characters[p.Key],Reason=(reasons.ContainsKey(p.Key)?reasons[p.Key]:"常用字补足")+(codePrefix.Length>0?" · "+codePrefix:"")}).ToList();
        }
        public static string Limit(string text,int count) {
            text=(text??"").Replace("\r","").Replace("\0","");
            return text.Length>count?text.Substring(text.Length-count):text;
        }
    }
}
