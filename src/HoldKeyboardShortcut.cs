namespace WubiCoach {
    // Mirrors macOS: hold Ctrl+Alt+K, consume repeats/up, release any modifier to hide.
    public sealed class HoldKeyboardShortcut {
        bool keyDown;
        public bool Visible {get;private set;}
        public bool Pressed {get;private set;}
        public bool Handle(int key,bool down,bool requiredModifiers) {
            if(key!=0x4B)return false;
            bool repeat=down&&keyDown;keyDown=down;
            if(Pressed) {if(!down){Pressed=false;Visible=false;}return true;}
            if(down&&!repeat&&requiredModifiers){Pressed=true;Visible=true;return true;}
            return false;
        }
        public void ModifiersChanged(bool requiredModifiers) {if(!requiredModifiers)Visible=false;}
        public void Reset() {keyDown=false;Pressed=false;Visible=false;}
    }
}
