using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace WubiCoach {
    public sealed class PinyinCharacter {
        public string Character;
        public string[] Readings;
    }
    // Same exact lookup, normalization and ordering as WubiCore/PinyinIndex.swift.
    public sealed class PinyinIndex {
        readonly Dictionary<string,List<PinyinCharacter>> buckets=new Dictionary<string,List<PinyinCharacter>>();
        public int CharacterCount {get;private set;}
        public PinyinIndex(string path,Dictionary<string,double> frequencies,HashSet<string> known) {
            foreach(var line in File.ReadLines(path,Encoding.UTF8).Skip(1)) {
                var p=line.Split('\t');
                if(p.Length!=2 || !(p[0].Length==1 && !char.IsSurrogate(p[0][0]) || p[0].Length==2 && char.IsSurrogatePair(p[0],0)))continue;
                var item=new PinyinCharacter {Character=p[0],Readings=p[1].Split(',')};
                CharacterCount++;
                foreach(var reading in item.Readings) {
                    List<PinyinCharacter> bucket;
                    if(!buckets.TryGetValue(reading,out bucket))buckets[reading]=bucket=new List<PinyinCharacter>();
                    bucket.Add(item);
                }
            }
            foreach(var bucket in buckets.Values)bucket.Sort(delegate(PinyinCharacter a,PinyinCharacter b) {
                double af,bf;frequencies.TryGetValue(a.Character,out af);frequencies.TryGetValue(b.Character,out bf);
                int score=bf.CompareTo(af);if(score!=0)return score;
                int knownOrder=known.Contains(b.Character).CompareTo(known.Contains(a.Character));
                return knownOrder!=0?knownOrder:char.ConvertToUtf32(a.Character,0).CompareTo(char.ConvertToUtf32(b.Character,0));
            });
        }
        public static string Normalize(string text) {
            string value=(text??"").Trim().ToLowerInvariant();
            if(value.Length==0 || value.Any(c=>c<'a'||c>'z'))return "";
            return value=="lue"?"lve":value=="nue"?"nve":value;
        }
        public IList<PinyinCharacter> Search(string query) {
            List<PinyinCharacter> result;
            return buckets.TryGetValue(Normalize(query),out result)?result.AsReadOnly():new List<PinyinCharacter>().AsReadOnly();
        }
    }
}
