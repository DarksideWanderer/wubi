using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;

namespace WubiCoach {
    // Local aggregate counts. The schema and ranking are shared with macOS.
    public sealed class PreferenceStore : IDisposable {
        IntPtr database;
        static readonly IntPtr Transient=new IntPtr(-1);
#if SQLITE_MAC_TEST
        const string Library="/usr/lib/libsqlite3.dylib";
#else
        const string Library="winsqlite3.dll";
#endif
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] file,out IntPtr db,int flags,IntPtr vfs);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db,int ms);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db,byte[] sql,int length,out IntPtr stmt,IntPtr tail);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_bind_text(IntPtr stmt,int index,byte[] text,int length,IntPtr destructor);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_changes(IntPtr db);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt,int column);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern long sqlite3_column_int64(IntPtr stmt,int column);
        [DllImport(Library,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_errmsg(IntPtr db);
        static byte[] Utf8(string s) {return Encoding.UTF8.GetBytes(s+"\0");}
        static string ReadUtf8(IntPtr p) {
            int length=0;while(Marshal.ReadByte(p,length)!=0)length++;
            var bytes=new byte[length];Marshal.Copy(p,bytes,0,length);return Encoding.UTF8.GetString(bytes);
        }
        Exception Failure() {return new IOException(ReadUtf8(sqlite3_errmsg(database)));}
        public PreferenceStore(string path) {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));
            try {
                if(sqlite3_open_v2(Utf8(path),out database,2|4|0x10000,IntPtr.Zero)!=0)throw Failure();
                sqlite3_busy_timeout(database,80);
                Execute("CREATE TABLE IF NOT EXISTS preferences (context TEXT NOT NULL, character TEXT NOT NULL, count INTEGER NOT NULL CHECK(count > 0), PRIMARY KEY(context, character)) WITHOUT ROWID");
            } catch {Dispose();throw;}
        }
        public void Dispose() {if(database!=IntPtr.Zero){sqlite3_close(database);database=IntPtr.Zero;}GC.SuppressFinalize(this);}
        ~PreferenceStore() {Dispose();}
        IntPtr Statement(string sql,params string[] args) {
            IntPtr stmt;
            if(sqlite3_prepare_v2(database,Utf8(sql),-1,out stmt,IntPtr.Zero)!=0) {if(stmt!=IntPtr.Zero)sqlite3_finalize(stmt);throw Failure();}
            for(int i=0;i<args.Length;i++) {
                var bytes=Utf8(args[i]);
                if(sqlite3_bind_text(stmt,i+1,bytes,bytes.Length-1,Transient)!=0){sqlite3_finalize(stmt);throw Failure();}
            }
            return stmt;
        }
        void Execute(string sql,params string[] args) {
            var stmt=Statement(sql,args);try {if(sqlite3_step(stmt)!=101)throw Failure();}finally {sqlite3_finalize(stmt);}
        }
        public static List<string> Contexts(string text) {
            var result=new List<string>{""};int length=0;
            for(int i=text.Length-1;i>=0&&length<3&&text[i]>='\u4e00'&&text[i]<='\u9fff';i--)length++;
            for(int n=1;n<=length;n++)result.Add(text.Substring(text.Length-n));return result;
        }
        public void Record(string context,string character,int weight) {
            if(weight<1||weight>8||character.Length!=1||character[0]<'\u4e00'||character[0]>'\u9fff')return;
            Execute("BEGIN IMMEDIATE");
            try {
                foreach(string suffix in Contexts(context)) {
                    Execute("UPDATE preferences SET count = MIN(count + "+weight+", 1000000000) WHERE context=? AND character=?",suffix,character);
                    if(sqlite3_changes(database)==0)Execute("INSERT INTO preferences(context,character,count) VALUES(?,?,"+weight+")",suffix,character);
                }
                Execute("COMMIT");
            } catch {try {Execute("ROLLBACK");}catch {}throw;}
        }
        public Dictionary<string,double> Scores(string context) {
            var result=new Dictionary<string,double>();var suffixes=Contexts(context);
            for(int n=0;n<suffixes.Count;n++) {
                var stmt=Statement("SELECT character,count FROM preferences WHERE context=?",suffixes[n]);
                try {
                    var bucket=new Dictionary<string,double>();int step;
                    while((step=sqlite3_step(stmt))==100)bucket[ReadUtf8(sqlite3_column_text(stmt,0))]=sqlite3_column_int64(stmt,1);
                    if(step!=101)throw Failure();double sum=bucket.Values.Sum();
                    foreach(var pair in bucket){double old;result.TryGetValue(pair.Key,out old);result[pair.Key]=old+Math.Pow(12,n)*pair.Value/sum;}
                }finally {sqlite3_finalize(stmt);}
            }
            return result;
        }
    }

    public sealed class PredictionColumns {
        public List<Candidate> Preferred,Regular;
        public List<Candidate> All {get {return Preferred.Concat(Regular).ToList();}}
    }
    public sealed class PersonalizedPredictor : IDisposable {
        readonly LearningEngine engine;
        readonly PreferenceStore store;
        public string Notice {get;private set;}
        public PersonalizedPredictor(LearningEngine engine,string databasePath) {
            this.engine=engine;Notice="";
            if(databasePath==null)return; // Isolated screenshot/demo mode does not learn.
            try {store=new PreferenceStore(databasePath);}catch(Exception e){Notice="偏好数据库不可用，使用常规联想："+e.Message;}
        }
        public void Dispose() {if(store!=null)store.Dispose();}
        public void Record(string context,string character,bool explicitSelection) {
            if(store==null||!engine.Characters.ContainsKey(character))return;
            try {store.Record(context,character,explicitSelection?4:1);Notice="";}catch(Exception e){Notice="偏好未保存："+e.Message;}
        }
        public PredictionColumns Predict(string context,string codePrefix) {
            var baseline=engine.Predict(context,codePrefix);string prefix=CompositionSnapshot.NormalizeCode(codePrefix);
            var scores=new Dictionary<string,double>();
            if(store!=null)try {scores=store.Scores(context);}catch(Exception e){Notice="偏好读取失败，使用常规联想："+e.Message;}
            var preferred=scores.OrderByDescending(p=>p.Value).ThenBy(p=>p.Key,StringComparer.Ordinal)
                .Where(p=>engine.Characters.ContainsKey(p.Key)).Select(p=>engine.Characters[p.Key])
                .Where(info=>prefix.Length==0||info.Code.StartsWith(prefix,StringComparison.Ordinal)||info.ShortCode.Split(' ').Any(c=>c.StartsWith(prefix,StringComparison.Ordinal)))
                .Take(9).Select(info=>new Candidate {Info=info,Reason="个人偏好"}).ToList();
            var seen=new HashSet<string>(preferred.Select(p=>p.Info.Character));
            foreach(var item in baseline)if(preferred.Count<9&&seen.Add(item.Info.Character))preferred.Add(item);
            return new PredictionColumns {Preferred=preferred,Regular=baseline.Where(p=>!seen.Contains(p.Info.Character)).Take(9).ToList()};
        }
    }
    public sealed class CommittedInputTracker {
        string previous="",code="",focus="";
        public void Clear() {previous=code=focus="";}
        public List<KeyValuePair<string,string>> Observe(string context,string nextCode,string nextFocus) {
            var result=new List<KeyValuePair<string,string>>();
            if(nextFocus.Length>0&&nextFocus==focus&&code.Length>0) {
                int overlap=previous.Length;
                if(!context.StartsWith(previous,StringComparison.Ordinal)) {
                    if(previous.Length==80&&context.Length==80) {
                        while(overlap>=Math.Max(1,previous.Length-4)&&previous.Substring(previous.Length-overlap)!=context.Substring(0,overlap))overlap--;
                    } else overlap=-1;
                }
                int count=context.Length-overlap;
                if(overlap>=Math.Max(0,previous.Length-4)&&count>=1&&count<=4&&previous.Substring(previous.Length-overlap)==context.Substring(0,overlap))
                    for(int i=overlap;i<context.Length;i++)result.Add(new KeyValuePair<string,string>(context.Substring(0,i),context[i].ToString()));
            }
            previous=context;code=nextCode;focus=nextFocus;return result;
        }
    }
}
