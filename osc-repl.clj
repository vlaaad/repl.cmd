;; TIL: OSC codes 133/633
;; 
;; OSC 133 and OSC 633 are “Operating System Command” escape sequences used by modern terminals and editors to delimit shell prompt and command output sections in the terminal stream.  
;; 
;; ### OSC 133
;; OSC 133 is a generic set of shell‑integration‑style escape sequences popularized by terminals like WezTerm, iTerm2, and others:
;; - `OSC 133;A` – the start of a shell prompt.  
;; - `OSC 133;B` – the end of the prompt.  
;; - `OSC 133;C` – the start of command execution (before output).  
;; - `OSC 133;D;exitcode` – the end of a command, with the exit code.  
;; 
;; ### OSC 633
;; OSC 633 is a similar but VS Code–specific, with richer metadata:
;; - `OSC 633;A` – prompt start.  
;; - `OSC 633;B` – prompt end.  
;; - `OSC 633;C` – command start (pre‑execution).  
;; - `OSC 633;D;exitcode` – command finished with exit code.  
;; - `OSC 633;E;command` – explicitly sets the command line (with optional nonce).  
;; 
;; These are used internally by VS Code to match commands, prompts, and exit codes in the terminal, enabling features like clickable restart‑run buttons and better history grouping.  
;; 


(require '[clojure.main])

(def ^:private esc-char (char 27))
(def ^:private bel-char (char 7))

(defn- osc [code]
  (str esc-char "]" code bel-char))

(defn- osc-escape [s]
  (apply str
         (map (fn [ch]
                (let [code (int ch)]
                  (cond
                    (= ch \\) "\\\\"
                    (<= code 32) (format "\\x%02x" code)
                    (= ch \;) "\\x3b"
                    :else (str ch))))
              (str s))))

(defn- cwd []
  (.getAbsolutePath (java.io.File. ".")))

(defn- emit! [& codes]
  (doseq [code codes]
    (print (osc code)))
  (flush))

(defn- emit-startup! []
  (let [windows? (.startsWith (System/getProperty "os.name") "Windows")
        dir (cwd)]
    (emit! (str "633;P;IsWindows=" (if windows? "True" "False"))
           "633;P;HasRichCommandDetection=True"
           (str "633;P;Cwd=" (osc-escape dir))
           (str "1337;CurrentDir=" dir))))

(defn- read-with-osc [request-prompt request-exit]
  (let [form (clojure.main/repl-read request-prompt request-exit)]
    (when-not (or (identical? form request-prompt)
                  (identical? form request-exit))
      (let [dir (cwd)]
        (emit! (str "633;P;Cwd=" (osc-escape dir))
               (str "1337;CurrentDir=" dir)
               (str "633;E;" (osc-escape (pr-str form)))
               "133;C"
               "633;C")))
    form))

(defn -main []
  (emit-startup!)
  (clojure.main/repl
   :read read-with-osc
   :prompt #(do
              (emit! "133;A" "633;A")
              (print "user=> ")
              (emit! "133;B" "633;B"))
   :print #(do
             (prn %)
             (emit! "133;D;0" "633;D;0"))
   :caught #(do
              (clojure.main/repl-caught %)
              (emit! "133;D;1" "633;D;1"))))

(-main)
