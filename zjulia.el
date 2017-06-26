;;; zjulia.el-1.0
;;; (Setq *zjulia-version-string* "1.0") ; update this below when changing.
;;;
;;; zjulia.el     - is a pair of modes for sending lines from a 
;;;                  script (sender) to a comint-started inferior 
;;;                  (receiver) process. We  use Ctrl-n by default as 
;;;                  the "send this line and step" key. This enables 
;;;                  one to step through scripts easily when working
;;;                  with an interpreter.
;;;
;;; License:      This minimal pair of (major and inferior) modes
;;;               was derived from the Emacs Octave Support modes in 
;;;               octave-mod.el and octave-inf.el, with a little help 
;;;               (and alot of inspiration) from the ess-mode.el for
;;;               R. As such it falls under the GNU General Public
;;;               License version 3 or later. The GPL applies solely
;;;               to this single file and does not apply to any
;;;               other files distributed here.
;;;
;;; Copyright (C) 2017, Author: Jason E. Aten
;;;
;;; how to install:
;;;
;;; (1) If you are changing which interpreter you want to use, examine
;;;     and adjust the "commonly-adjusted parameters" section just below.
;;;
;;; (2) Copy zjulia-mode.el into your ~/.emacs.d/  directory.
;;;
;;; (3) Then put this in your .emacs:
;;;
;;;    (load "/home/jaten/.emacs.d/zjulia.el") ; adjust path to fit your home directory.
;;;    (require 'zjulia-mode)
;;;    (global-set-key "\C-n" 'zjulia-send-line)
;;;
;;; (4) Optionally for speed, M-x byte-compile-file <enter> 
;;;                           ~/.emacs.d/zjulia.el <enter>
;;;
;;; (5) To use, do 'M-x run-zjulia' to start the interpreter. Open
;;;     your script and in the script buffer do 'M-x zjulia-mode'.
;;;
;;;     Or, open a file with an automatically recognized extension
;;;     (as specified below) and press 'C-n' on the first line
;;;     you want executed in the interpreter.


;; To over-ride parameters, skip down to the "commonly-adjusted
;; parameters" section below these declarations.
;;
;; Here we just document the typically overriden parameters of interest.
;; NB: these just give defaults, which the setq settings below will override.
;; Putting them here keeps the byte-compiler from complaining.

(defvar *inferior-zjulia-program* "julia"
  "Program invoked by `inferior-zjulia'.")

(defvar *inferior-zjulia-buffer* "*zjulia*"
  "*Name of buffer for running an inferior zjulia process.")

(defvar *inferior-zjulia-regex-prompt* "[^\(julia>\)\|\(\.\.\.\)]*[> ]"
  "Regexp to match prompts for the inferior Zjulia process.")

(setq *inferior-zjulia-regex-prompt* "[^\(julia>\)\|\(\.\.\.\)]*[> ]")

(defvar *zjulia-keypress-to-sendline* (kbd "C-n")
  "keypress that, when in a pure mode script, sends a line to the interpreter
   and then steps to the next line.")

(defvar *zjulia-keypress-to-send-sexp-jdev*      (kbd "C-u")
  "keypress that sends the next sexp to the repl, and advances past it.")

(defvar *zjulia-keypress-to-send-sexp-jdev-prev* (kbd "C-p")
  "keypress that sends the previous sexp to the repl")

(defvar *zjulia-version-string* "1.0"
  "version of zjulia.el currently running.")


;; ================================================
;; ================================================
;; begin commonly-adjusted parameters

;; the name of the interpreter to run
;(setq *inferior-zjulia-program*  "/Users/jaten/bin/zjulia")
(setq *inferior-zjulia-program*  "julia")

;; the name of the buffer to run the interpreter in
(setq *inferior-zjulia-buffer* "*zjulia*")

;; the comment character
(setq *inferior-zjulia-comment-char* "#")

(setq  comment-start   *inferior-zjulia-comment-char*)
(setq  comment-end     nil)
(setq  comment-column  4)


;; file extensions that indicate we should automatically enter zjulia mode...
(setq auto-mode-alist (cons '("\\.zy$" . zjulia-mode) auto-mode-alist))


;; regexp to know when interpreter output is done and we are at a prompt.
;;(setq *inferior-zjulia-regex-prompt*  "[^\(julia>\)\|\(\.\.\.\)]*[> ]")

;; keypress that, when in a zjulia-mode script, sends a line to the interpreter
;;  and then steps to the next line.
(setq *zjulia-keypress-to-sendline* (kbd "C-n"))

;; keypress that, when in a zjulia-mode script, sends an sexp to the repl
;;  and then steps to the next line.
(setq *zjulia-keypress-to-send-sexp-jdev*      (kbd "C-9"))
(setq *zjulia-keypress-to-send-sexp-jdev-prev* (kbd "C-p"))

;; end commonly-adjusted parameters
;; ================================================
;; ================================================


(defvar inferior-zjulia-output-list nil)
(defvar inferior-zjulia-output-string nil)
(defvar inferior-zjulia-receive-in-progress nil)
(defvar inferior-zjulia-process nil)

(defvar zjulia-mode-hook nil
  "*Hook to be run when Zjulia mode is started.")

(defvar zjulia-send-show-buffer t
  "*Non-nil means display `*inferior-zjulia-buffer*' after sending to it.")
(setq zjulia-send-show-buffer t)

(defvar zjulia-send-line-auto-forward nil
  "*Control auto-forward after sending to the inferior Zjulia process.
Non-nil means always go to the next Zjulia code line after sending.")

(setq zjulia-send-line-auto-forward nil)

(defvar zjulia-send-echo-input t
  "*Non-nil means echo input sent to the inferior Zjulia process.")
(setq zjulia-send-echo-input t)

(defvar *zjulia-known-lisps*) 
(setq *zjulia-known-lisps* '((:sysname "ccl" :syspath "/home/jaten/uns/bin/ccl64" :syspromptregex "[^[?]]*[?] ")
			    (:sysname "sbcl" :syspath "/usr/bin/sbcl" :syspromptregex "[^>]*> ")
			    (:sysname "cmucl" :syspath "/usr/local/bin/lisp" :syspromptregex "[^>]*> ")))


;; try to hide the ctrl-M carriage returns that ipython generates.
(defun remove-dos-eol ()
  "Do not show ^M in files containing mixed UNIX and DOS line endings."
  (interactive)
  (with-current-buffer *inferior-zjulia-buffer* 
    (setq buffer-display-table (make-display-table))
    (aset buffer-display-table ?\^M [])))


;;; Motion
(defun zjulia-next-code-line (&optional arg)
  "Move ARG lines of Zjulia code forward (backward if ARG is negative).
Skips past all empty and comment lines.  Default for ARG is 1.

On success, return 0.  Otherwise, go as far as possible and return -1."
  (interactive "p")
  (or arg (setq arg 1))
  (beginning-of-line)
  (let ((n 0)
	(inc (if (> arg 0) 1 -1)))
    (while (and (/= arg 0) (= n 0))
      (setq n (forward-line inc))
      (while (and (= n 0)
		  (looking-at "\\s-*\\($\\|\\s<\\)"))
	(setq n (forward-line inc)))
      (setq arg (- arg inc)))
    n))

(defun zjulia-previous-code-line (&optional arg)
  "Move ARG lines of Zjulia code backward (forward if ARG is negative).
Skips past all empty and comment lines.  Default for ARG is 1.

On success, return 0.  Otherwise, go as far as possible and return -1."
  (interactive "p")
  (or arg (setq arg 1))
  (zjulia-next-code-line (- arg)))


;;; Communication with the inferior Zjulia process
(defun zjulia-kill-process ()
  "Kill inferior Zjulia process and its buffer."
  (interactive)
  (if inferior-zjulia-process
      (progn
	(process-send-string inferior-zjulia-process "quit;\n")
	(accept-process-output inferior-zjulia-process)))
  (if *inferior-zjulia-buffer*
      (kill-buffer *inferior-zjulia-buffer*)))

(defun zjulia-show-process-buffer ()
  "Make sure that `*inferior-zjulia-buffer*' is displayed."
  (interactive)
  (if (get-buffer *inferior-zjulia-buffer*)
      (display-buffer *inferior-zjulia-buffer*)
    (message "No buffer named %s" *inferior-zjulia-buffer*)))

(defun zjulia-hide-process-buffer ()
  "Delete all windows that display `*inferior-zjulia-buffer*'."
  (interactive)
  (if (get-buffer *inferior-zjulia-buffer*)
      (delete-windows-on *inferior-zjulia-buffer*)
    (message "No buffer named %s" *inferior-zjulia-buffer*)))

(defun zjulia-send-region (beg end)
  "Send current region to the inferior Zjulia process."
  (interactive "r")
  (inferior-zjulia t)
  (let ((proc inferior-zjulia-process)
	(string (buffer-substring-no-properties beg end))
	line)
    (if (string-equal string "")
	(setq string "\n"))
    (with-current-buffer *inferior-zjulia-buffer* 
      (setq inferior-zjulia-output-list nil)
      (while (not (string-equal string ""))
	(if (string-match "\n" string)
	    (setq line (substring string 0 (match-beginning 0))
		  string (substring string (match-end 0)))
	  (setq line string string ""))
	(setq inferior-zjulia-receive-in-progress t)
	(inferior-zjulia-send-list-and-digest (list (concat line "\n")))
;;	(inferior-zjulia-send-list-and-digest (list (concat "%cpaste\n" line "\n--\n")))
	(while inferior-zjulia-receive-in-progress
	  (accept-process-output proc))
	(insert-before-markers
	 (mapconcat 'identity
		    (append
		     (if zjulia-send-echo-input (list line) (list ""))
		     (mapcar 'inferior-zjulia-strip-ctrl-g
			     inferior-zjulia-output-list)
		     (list inferior-zjulia-output-string))
		    "\n")))))
  (if zjulia-send-show-buffer
      (zjulia-eob)))
       


;; test out moving the inf buffer to end...
(defun zjulia-eob ()
  (interactive)
  (let* ((mywin (display-buffer *inferior-zjulia-buffer*))
	 (bl (with-current-buffer *inferior-zjulia-buffer*
	       (line-number-at-pos (point-min))))
	 (cl (with-current-buffer *inferior-zjulia-buffer*
	       (line-number-at-pos (window-point mywin))))
	 (el (with-current-buffer *inferior-zjulia-buffer*
	       (goto-char (point-max))
	       (line-number-at-pos))))
    ;;;(message "bl is %d,    el is %d, cl is %d,  el-cl is %d" bl el cl (- el cl))
    (setq other-window-scroll-buffer (get-buffer *inferior-zjulia-buffer*))
    (scroll-other-window (- el cl))
    (with-current-buffer *inferior-zjulia-buffer*
      (goto-char (point-max))
      (set-window-point mywin (point-max)))
    (display-buffer *inferior-zjulia-buffer*)
    ))




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; the entire point of zjulia-mode : to enable the use
;; of zjulia-send-line with a single keypress.
;;
(defun zjulia-send-line (&optional arg)
  "Send current Zjulia code line to the inferior Zjulia process.
With positive prefix ARG, send that many lines.
If `zjulia-send-line-auto-forward' is non-nil, go to the next unsent
code line."
  (interactive "P")
  (or arg (setq arg 1))
  (if (> arg 0)
      (let (beg end)
	(beginning-of-line)
	(setq beg (point))
	(zjulia-next-code-line (- arg 1))
	(end-of-line)
	(setq end (point))
	(if zjulia-send-line-auto-forward
	    (zjulia-next-code-line 1)
	  (forward-line 1))
	(zjulia-send-region beg end))))

;;;;;;; sexp-based version -- hard code in *inferior-zjulia-buffer*, and remove SLIME dependencies.

;;;;;;;;;;;  zjulia-advance-and-eval-sexp-jdev    and   zjulia-advance-and-eval-sexp-jdev-prev


(defun nil-to-point-max (x)
  (if x 
      x 
    (point-max)
))

(defun nil-to-point-min (x)
  (if x 
      x 
    (point-min)
))

(defun skip-lisp-comment-lines ()
  "skip over lines that start with // before they have another non-whitespace character"
  (interactive)
  (let* ((done-skipping)
	 (startp (point))
	 (nextcomment)
	 (eol)
	 (nextword)
	 )
    ;; 
    ;; if nextcomment < eol and ( nextword > nextcomment or nextword is nil ) then skip to next line

    ;; conversely, if nextword < eol and (nextcomment is nil or nextword < nextcomment) then stop skipping lines
    (while (not done-skipping)
      (setq startp        (point))
      (setq nextcomment   (nil-to-point-max (search-forward *inferior-zjulia-comment-char* nil 0 1)))
      (setq eol           (progn (goto-char startp) (nil-to-point-max (search-forward "\n" nil 0 1))))
      (setq nextword      (progn (goto-char startp) (+ (point) (skip-chars-forward "\t ;\n"))))
      
      ;; either stop at the word, or go to the end of line
      (if (< nextword eol)
	  (if (or (< nextword nextcomment)
		  (= (point-max) nextcomment))
	      
	      (progn
		(setq done-skipping t)
		(goto-char nextword)
		)

	    (goto-char eol))
	(progn
	  (when (= nextword eol)
	      (setq done-skipping t) ;; stop if nextword == eol
	      )
	  (goto-char eol)
	  )
	)
      )
    )
  )

(defvar DEBUG_STATUS 'off
  "DEBUG_STATUS controls the DEBUG macro's behavior; legit values are 'on or 'off.")

;(setq DEBUG_STATUS 'on)
(setq DEBUG_STATUS 'off)

(defmacro DEBUG (&rest body)
  "DEBUG is simple call to (@body) or nil, depending on the value of DEBUG_STATUS being 'on or not. 
Makes it easy to debug when needed. You will have to recompile, of course, in order for the
macro to be able to take effect, if you change the value of DEBUG_STATUS. For efficiency's
sake, this is a compile time, not a runtime, convenience."
  (if (eql DEBUG_STATUS 'on)
      `(,@body)
    'nil)
)

;; test
;; (DEBUG message "startp       is %s" startp)
;; (macroexpand '(DEBUG message "startp       is %s" startp))


(defun line-is-comment-or-whitespace ()
  "determine if this line can be ignored because it is just a comment or whitespace"
  (interactive)
  (DEBUG message "***************** starting: (line-is-comment-or-whitespace), at %S" (line-number-at-pos))
  (block block-line-is-comment-or-whitespace
  (let* ((startp (point))
	 (nextword nil)
	 (nextcomment nil)
	 (bol nil)
	 (eol nil)
	 (prevbol nil)
	 )

      (setq startp        (point))
      (setq bol           (progn (goto-char startp)                         (nil-to-point-min (search-backward "\n" 0 0 1))))
      (setq prevbol       (progn (goto-char (max (point-min) (- bol 1)))    (nil-to-point-min (search-backward "\n" 0 0 1))))
      (setq nextcomment   (progn (goto-char bol)                            (nil-to-point-max (search-forward *inferior-zjulia-comment-char* nil 0 1))))
      (setq eol           (progn (goto-char startp)                         (nil-to-point-max (search-forward "\n" nil 0 1))))
      (setq nextword      (progn (goto-char bol)                            (+ (point) (skip-chars-forward "\t ;\n"))))

      (goto-char startp)

      (DEBUG message "startp       is %s" startp)
      (DEBUG message "bol          is %s" bol)
      (DEBUG message "eol          is %s" eol)
      (DEBUG message "prevbol      is %s" prevbol)
      (DEBUG message "nextcomment  is %s" nextcomment)
      (DEBUG message "nextword     is %s" nextword)

      ;; when startp == 1 + bol, and nextcomment == 1 + startp, then we have a line of all comments
      (when (and (= startp (+ 1 bol))
		 (= nextcomment (+ 1 startp)))
	(DEBUG message "line is empty, returning t early")
	(return-from block-line-is-comment-or-whitespace t))

      ;; sanity check for empty lines
      (when (and (= eol (+ 1 startp))
		 (= bol (- startp 1))
		 )
	(progn 
	  (DEBUG message "line is empty, returning t early")
	  (return-from block-line-is-comment-or-whitespace t)))


      ;; if nextword    > eol this is skippable.
      (when (> nextword eol)
	(progn
	  (DEBUG message "nextword > eol, returning t early")
	  (return-from block-line-is-comment-or-whitespace t)))


      ;; INVAR: bol < nextword < eol, only question left: is there a comment before the nextword?

      (if (or (> nextcomment eol)
	      (< nextcomment bol))
	  
	  ;; nextcomment is not in play
	  (progn
	    (DEBUG message "nil: cannot skip b/c bol < nextword < eol, and no comment present on this line.")
	    (return-from block-line-is-comment-or-whitespace nil))
	
	;; INVAR: comment is in play, and may obscucate the entire line.
	(if (<= nextcomment nextword)
	    (progn
	      (DEBUG message "t: can skip")
	      (return-from block-line-is-comment-or-whitespace t))
	  
	  ;;
	  (progn
	    (DEBUG message "nil: cannot skip b/c bol < nextword < nextcomment < eol.")
	    (return-from block-line-is-comment-or-whitespace nil)))

	) ;; endif 
)))


(defun skip-lisp-comment-lines-backwards ()
  "Going backwards, skip over lines that start with semi-colons before they have another non-whitespace character.
The main side-effect is to reposition point. The function returns the new position of point, 
which is just following the next form back."

  (interactive)
  (DEBUG message "***************** starting: (skip-lisp-comment-lines-backwards)")
  (block block-skip-lisp-comment-lines-backwards
    (DEBUG message "--> point is starting at %s" (point))
    (let* ((startp (point))
	   (next-word-back)
	   (bol)
	   (nextcomment)
	   (eol)
	   (start-backwards-search)
	   (starting-line (line-number-at-pos))
	   (cur-line      starting-line)
	   )
      
      ;; back up until we find a line with something like a lisp form on it (and the whole line is not commented out)
      (beginning-of-line)

      ;; handle the case of starting at the beginning of a non-comment line, by backing up one line before we search...
      (when (and (= (point) startp)
		 (> startp  (point-min)))
	;; we started at the beginning of a line, and it's not the first line, so back up past the newline to prev line.
	(goto-char (- startp 1))
	(beginning-of-line))
      
      ;; main backup while loop
      (while (and (line-is-comment-or-whitespace)
		  (> (point) (point-min)))
	(forward-line -1)
	)

      ;; if we have moved lines, reset to our new starting place...
      (setq cur-line (line-number-at-pos))
      (if (= cur-line starting-line)
	  (goto-char startp)
	(progn
	  (end-of-line)
	  (setq startp (point))))
      (DEBUG message "--> After revision of backing up past comments, point is at %s" (point))


      ;; INVAR: we are on a line with some content, or we are at the beginning of the buffer
      (when (line-is-comment-or-whitespace)
	;; beginning of buffer, just get to the start.
	(goto-char (point-min)) 
	(return-from block-skip-lisp-comment-lines-backwards (point-min)))
	  
      (DEBUG message "--> INVAR: we are on a line with some content")
    
      (setq bol           (progn (goto-char startp)                         (nil-to-point-min (search-backward "\n" 0 0 1))))
      (setq nextcomment   (progn (goto-char bol)                            (nil-to-point-max (search-forward *inferior-zjulia-comment-char* nil 0 1))))
      (setq eol           (progn (goto-char startp)                         (nil-to-point-max (search-forward "\n" nil 0 1))))

      ;; start from eol, or from nextcomment if nextcomment is < eol
      (setq start-backwards-search eol)
      (when (< nextcomment eol)
	(setq start-backwards-search nextcomment))

      (setq next-word-back 
	    (progn 
	      (goto-char start-backwards-search)    
	      (+ 
	       (point) 
	       (skip-chars-backward "\t ;\n"))))

      (goto-char next-word-back)
)))

;; debug bindings
;;  (global-set-key "\C-o" 'skip-lisp-comment-lines-backwards)
;;  (global-set-key "\C-o" 'line-is-comment-or-whitespace)
;;  (global-set-key "\C-o"   'my-backward-sexp-ignoring-comments)
  (global-set-key "\C-o"   '(forward-line -1))


  
(defun my-forward-sexp-ignoring-comments ()
  "Move forward across one balanced expression (sexp), ignoring ; comments"
  (interactive "^p")

  ;; at end of file? return early
  (if (= (point) (point-max))
      nil
    (progn
      ;; rest of function is in this big else block; we could also do try/catch (maybe later), but this is clearer.
      
      ;; first determine if we are in a comment: iff there is a semi-colon between (point) and previous newline or beginning of buffer
      ;; if we are in a comment, then go to the next line.
      ;; now skip over any additional comments, arriving at the first uncommented sexp
      (setq startp (point))
      
      (search-backward "\n" 0 0 1) ;; side effect is to move point to beginning of line
      (setq bol    (point))
      
      ;; find previous comment
      (goto-char startp) ;; start over
      (search-backward *inferior-zjulia-comment-char* 0 0 1) 
      (setq prevcomment (point))
      
      ;; find previous double quote
      (goto-char startp) ;; start over
      (search-backward "\"" 0 0 1)
      (setq prevdoublequote (point))
      
      ;; find end of line
      (search-forward "\n" nil 0 1)
      (setq eol (point))
      (if (not (string= "\n" (buffer-substring startp (+ 1 startp))))
	  (goto-char startp))
      
      ;; rely on the fact that we are now at the beginning of the next line, and check for comments.
      ;; If there is a comment character that is both >= bol and also > prevdoublequote, then skip to next line
      ;; otherwise start over and return to original starting position.
      (unless (and (>= prevcomment bol) (> prevcomment prevdoublequote))
	(goto-char startp))
      
      ;; INVAR: we are at the beginning of a line or at the beginning of a non-commented sexp.
      (skip-lisp-comment-lines) ;; call the above function to handle skipping to the next sexp.
      
      (forward-sexp)
    ;(skip-lisp-comment-lines) ;; get to the beginning of the next form
      )))


(defun my-backward-sexp-ignoring-comments ()
  "Move backward across one balanced expression (sexp), ignoring comments in the form of semicolons"
  (interactive)
  (DEBUG message "******** starting: my-backward-sexp-ignoring-comments")

  ;; at beginning of file? return early
  (if (= (point) (point-min))
      nil
    (progn
      ;; rest of function is in this big else block; we could also do try/catch (maybe later), but this is clearer.

      (skip-lisp-comment-lines-backwards)
      (if (line-is-comment-or-whitespace)
	  (progn
	    (DEBUG message "*************************** my-backward-sexp-ignoring-comments: finishing with (beginning-of-line) and t <<<<<")
	    (beginning-of-line)
	    t)
	(progn
	  (DEBUG message "*************************** my-backward-sexp-ignoring-comments: finishing with (backward-sexp) and t <<<<<")
	  (backward-sexp)
	  t)
	))))


(defun zjulia-advance-and-eval-sexp-jdev ()
       "advance one sexp, and copy that sexp into the
*inferior-zjulia-buffer*, so as to step through lines in a lisp .cl file"
       (interactive)
       (inferior-zjulia t)
       (setq clisp-buf *inferior-zjulia-buffer*)
       (setq pstart (point))
       (push-mark)
       (my-forward-sexp-ignoring-comments)
       (setq pend (point))
       (skip-zjulia-comment-lines) ;; get to the beginning of the next form, so point is at the beginning of next line.
       ;;(setq str (buffer-substring pstart pend))
       (with-current-buffer clisp-buf (goto-char (point-max)))
       (append-to-buffer clisp-buf pstart pend)
       (with-current-buffer clisp-buf 
	 (setq comint-eol-on-send t)
	 (setq comint-process-echoes nil)
	 (setq comint-move-point-for-output t)
	 (zjulia-send-input)
	 (display-buffer clisp-buf)
	 (recenter)
))
	 

(defun zjulia-advance-and-eval-sexp-jdev-prev ()
       "copy the previous sexp into the *inferior-zjulia-buffer*"
       (interactive)
       (inferior-zjulia t)
       (setq clisp-buf *inferior-zjulia-buffer*)
       (if (and (my-backward-sexp-ignoring-comments)
		  (not (line-is-comment-or-whitespace)))
	   (progn
	     (setq pstart (point))
	     (push-mark)
	     (forward-sexp)
	     (setq pend (point))
	     (with-current-buffer clisp-buf (goto-char (point-max)))
	     (append-to-buffer clisp-buf pstart pend)
	     (with-current-buffer clisp-buf 
	       (setq comint-eol-on-send t)
	       (setq comint-process-echoes nil)
	       (setq comint-move-point-for-output t)
	       (zjulia-send-input)
	       (display-buffer clisp-buf)
	       (recenter)
	       )
	     ;;(skip-zjulia-comment-lines)
	     )
	 (beginning-of-line)))


;;;;;;;;;;;; simplest possible major mode stuff

(defvar zjulia-mode-map nil
  "Local keymap for zjulia mode buffers.")

(setq zjulia-mode-map nil)

(if zjulia-mode-map
    nil
  (setq zjulia-mode-map (make-sparse-keymap))
  (define-key zjulia-mode-map *zjulia-keypress-to-sendline* 'zjulia-send-line)
  (define-key zjulia-mode-map *zjulia-keypress-to-send-sexp-jdev* 'zjulia-advance-and-eval-sexp-jdev)
  (define-key zjulia-mode-map *zjulia-keypress-to-send-sexp-jdev-prev* 'zjulia-advance-and-eval-sexp-jdev-prev)
)

(defun zjulia-mode ()
  "simple send-line, aka zjulia mode."
  (interactive)
  (kill-all-local-variables)
  (setq major-mode 'zjulia-mode)
  (setq mode-name "zjulia")
  (use-local-map zjulia-mode-map)

  ;; borrow the setup for lisp mode indentation from the other emacs lisp modes.
  (lisp-mode-variables  t)

  (run-mode-hooks 'zjulia-mode-hook))


;;; provide ourself

;;;(provide 'zjulia-mod)

;;; zjulia-mod.el ends here


;;; zjulia-inf.el --- running zjulia as an inferior Emacs process

;;(require 'zjulia-mod)
(require 'comint)

(defgroup zjulia-inferior nil
  "Running Zjulia as an inferior Emacs process."
  :group 'zjulia)




(defvar inferior-zjulia-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map comint-mode-map)
    map)
  "Keymap used in Inferior Zjulia mode.")

(defvar inferior-zjulia-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?\` "w" table)
    table)
  "Syntax table in use in inferior-zjulia-mode buffers.")

(defvar inferior-zjulia-mode-hook nil
  "*Hook to be run when Inferior Zjulia mode is started.")


(defvar *inferior-zjulia-startup-args* nil
  "arguments to be given to the Inferior Zjulia process on startup.")
;(setq *inferior-zjulia-startup-args* (list "console" "--nosep" "--colors=NoColor"))

;;; Compatibility functions
(if (not (fboundp 'comint-line-beginning-position))
    ;; comint-line-beginning-position is defined in Emacs 21
    (defun comint-line-beginning-position ()
      "Returns the buffer position of the beginning of the line, after
any prompt. The prompt is assumed to be any text at the beginning of the 
line matching the regular expression `comint-prompt-regexp', a buffer local 
variable."
      (save-excursion (comint-bol nil) (point))))


(defvar inferior-zjulia-output-list nil)
(defvar inferior-zjulia-output-string nil)
(defvar inferior-zjulia-receive-in-progress nil)
(defvar inferior-zjulia-startup-hook nil)


(defun inferior-zjulia-mode ()
  "Major mode for interacting with an inferior Zjulia process.
Runs Zjulia as a subprocess of Emacs, with Zjulia I/O through an Emacs
buffer.

Entry to this mode successively runs the hooks `comint-mode-hook' and
`inferior-zjulia-mode-hook'."
  (interactive)
  (delay-mode-hooks (comint-mode))
  (setq comint-prompt-regexp *inferior-zjulia-regex-prompt*
	major-mode 'inferior-zjulia-mode
	mode-name "Inferior Zjulia"
	mode-line-process '(":%s"))
  (use-local-map inferior-zjulia-mode-map)
  (setq comint-input-ring-file-name
	(or (getenv "ZJULIA_HISTFILE") "~/.zjulia_hist")
	comint-input-ring-size (or (getenv "ZJULIA_HISTSIZE") 1024))
  (comint-read-input-ring t)

  (make-local-variable 'kill-buffer-hook)
  (add-hook 'kill-buffer-hook 'zjulia-kill-buffer-function)

  (run-mode-hooks 'inferior-zjulia-mode-hook))

;;;###autoload
(defun inferior-zjulia (&optional arg)
  "Run an inferior Zjulia process, I/O via `*inferior-zjulia-buffer*'.
This buffer is put in Inferior Zjulia mode.  See `inferior-zjulia-mode'.

Unless ARG is non-nil, switches to this buffer.

The elements of the list `*inferior-zjulia-startup-args*' are sent as
command line arguments to the inferior Zjulia process on startup.

Additional commands to be executed on startup can be provided either in
the file specified by `inferior-zjulia-startup-file' or by the default
startup file, `~/.emacs-zjulia'."
  (interactive "P")
  (let ((buffer *inferior-zjulia-buffer*))
    (get-buffer-create buffer)
    (if (comint-check-proc buffer)
	()
      (with-current-buffer buffer
	(comint-mode)
	(inferior-zjulia-startup)
	(inferior-zjulia-mode)))
    (if (not arg)
	(pop-to-buffer buffer))))

;;;###autoload
(defalias 'run-zjulia 'inferior-zjulia)

(defun inferior-zjulia-startup ()
  "Start an inferior Zjulia process."
  (let ((proc (comint-exec-1
	       (substring *inferior-zjulia-buffer* 1 -1)
	       *inferior-zjulia-buffer*
	       *inferior-zjulia-program*
	       *inferior-zjulia-startup-args*)))
    (set-process-filter proc 'inferior-zjulia-output-filter)
    (setq comint-ptyp process-connection-type
	  inferior-zjulia-process proc
	  inferior-zjulia-output-list nil
	  inferior-zjulia-output-string nil
	  inferior-zjulia-receive-in-progress t)

    (remove-dos-eol)
    (run-hooks 'inferior-zjulia-startup-hook)
    (run-hooks 'inferior-zjulia-startup-hook)))


(defun inferior-zjulia-strip-ctrl-m (string)
  (while (string-match "\r$" string)
      (setq string (concat (substring string 0 (- (length string) 1)) "\n")))
  string)

;; test:
;; (inferior-zjulia-strip-ctrl-m "hi")



(defun inferior-zjulia-strip-ctrl-g (string)
  "Strip leading `^G' character.
If STRING starts with a `^G', ring the bell and strip it."
  (if (string-match "^\a" string)
      (progn
        (ding)
        (setq string (substring string 1))))
  string)

(defun inferior-zjulia-output-filter (proc string)
  "Standard output filter for the inferior Zjulia process.
Ring Emacs bell if process output starts with an ASCII bell, and pass
the rest to `comint-output-filter'."
;;  (comint-output-filter proc (inferior-zjulia-strip-ctrl-m (inferior-zjulia-strip-ctrl-g string))))
  (comint-output-filter proc (inferior-zjulia-strip-ctrl-g string)))

(defun inferior-zjulia-output-digest (proc string)
  "Special output filter for the inferior Zjulia process.
Save all output between newlines into `inferior-zjulia-output-list', and
the rest to `inferior-zjulia-output-string'."
  (setq string (concat inferior-zjulia-output-string string))
  (while (string-match "\n" string)
    (setq inferior-zjulia-output-list
	  (append inferior-zjulia-output-list
		  (list (substring string 0 (match-beginning 0))))
	  string (substring string (match-end 0))))
  (if (string-match *inferior-zjulia-regex-prompt* string)
      (setq inferior-zjulia-receive-in-progress nil))
  (setq inferior-zjulia-output-string string))

(defun inferior-zjulia-send-list-and-digest (list)
  "Send LIST to the inferior Zjulia process and digest the output.
The elements of LIST have to be strings and are sent one by one.  All
output is passed to the filter `inferior-zjulia-output-digest'."
  (let* ((proc inferior-zjulia-process)
	 (filter (process-filter proc))
	 string)
    (set-process-filter proc 'inferior-zjulia-output-digest)
    (setq inferior-zjulia-output-list nil)
    (unwind-protect
	(while (setq string (car list))
	  (setq inferior-zjulia-output-string nil
		inferior-zjulia-receive-in-progress t)
	  (comint-send-string proc string)
	  (while inferior-zjulia-receive-in-progress
	    (accept-process-output proc))
	  (setq list (cdr list)))
      (set-process-filter proc filter))))


(defun zjulia-kill-buffer-function nil
  "Function run just before an ZJULIA process buffer is killed.
  This simply deletes the buffers process to avoid an Emacs bug
  where the sentinel is run *after* the buffer is deleted."
  (let ((proc (get-buffer-process (current-buffer))))
    (if proc (delete-process proc))))




(defun zjulia-send-input ()
  "zjulia-send-input: send input to both comint-send-input  and  another process of your choice"
  (interactive)
  ;; other send goes here
  (comint-send-input)
)

(defun skip-zjulia-comment-lines ()
  "skip over lines that start with // before they have another non-whitespace character"
  (interactive)
  (DEBUG message "skip-zjulia-comment-lines running")
  (let* ((done-skipping)
	 (startp (point))
	 (nextcomment)
	 (eol)
     (bol nil)
     (eol nil)
     (prevbol nil)
	 (nextword)
	 )
    ;; 
    ;; if nextcomment < eol and ( nextword > nextcomment or nextword is nil ) then skip to next line

    ;; conversely, if nextword < eol and (nextcomment is nil or nextword < nextcomment) then stop skipping lines
    (while (not done-skipping)
      (setq startp        (point))
      (setq nextcomment   (nil-to-point-max (search-forward *inferior-zjulia-comment-char* nil 0 1)))
      (setq eol           (progn (goto-char startp) (nil-to-point-max (search-forward "\n" nil 0 1))))
      (setq nextword      (progn (goto-char startp) (+ (point) (skip-chars-forward "\t ;\n"))))

      ;; debug stuff
      (setq bol           (progn (goto-char startp)                         (nil-to-point-min (search-backward "\n" 0 0 1))))
      (setq prevbol       (progn (goto-char (max (point-min) (- bol 1)))    (nil-to-point-min (search-backward "\n" 0 0 1))))

      (goto-char startp)

      (DEBUG message "startp       is %s" startp)
      (DEBUG message "bol          is %s" bol)
      (DEBUG message "eol          is %s" eol)
      (DEBUG message "prevbol      is %s" prevbol)
      (DEBUG message "nextcomment  is %s" nextcomment)
      (DEBUG message "nextword     is %s" nextword)

      ;; end debug stuff
      
      ;; either stop at the word, or go to the end of line
      (if (< nextword eol)
	  (if (or (< nextword nextcomment)
		  (= (point-max) nextcomment))
	      
	      (progn
		(setq done-skipping t)
		(goto-char nextword)
		)

	    (goto-char eol))
	(progn
	  (when (= nextword eol)
	      (setq done-skipping t) ;; stop if nextword == eol
	      )
	  (goto-char eol)
	  )
	)
      )
    )
  )


(defun skip-zjulia-comment-lines-backwards ()
  "Going backwards, skip over lines that start with semi-colons before they have another non-whitespace character.
The main side-effect is to reposition point. The function returns the new position of point, 
which is just following the next form back."

  (interactive)
  (DEBUG message "***************** starting: (skip-zjulia-comment-lines-backwards)")
  (block block-skip-zjulia-comment-lines-backwards
    (DEBUG message "--> point is starting at %s" (point))
    (let* ((startp (point))
	   (next-word-back)
	   (bol)
	   (nextcomment)
	   (eol)
	   (start-backwards-search)
	   (starting-line (line-number-at-pos))
	   (cur-line      starting-line)
	   )
      
      ;; back up until we find a line with something like a lisp form on it (and the whole line is not commented out)
      (beginning-of-line)

      ;; handle the case of starting at the beginning of a non-comment line, by backing up one line before we search...
      (when (and (= (point) startp)
		 (> startp  (point-min)))
	;; we started at the beginning of a line, and it's not the first line, so back up past the newline to prev line.
	(goto-char (- startp 1))
	(beginning-of-line))
      
      ;; main backup while loop
      (while (and (line-is-comment-or-whitespace)
		  (> (point) (point-min)))
	(forward-line -1)
	)

      ;; if we have moved lines, reset to our new starting place...
      (setq cur-line (line-number-at-pos))
      (if (= cur-line starting-line)
	  (goto-char startp)
	(progn
	  (end-of-line)
	  (setq startp (point))))
      (DEBUG message "--> After revision of backing up past comments, point is at %s" (point))


      ;; INVAR: we are on a line with some content, or we are at the beginning of the buffer
      (when (line-is-comment-or-whitespace)
	;; beginning of buffer, just get to the start.
	(goto-char (point-min)) 
	(return-from block-skip-zjulia-comment-lines-backwards (point-min)))
	  
      (DEBUG message "--> INVAR: we are on a line with some content")
    
      (setq bol           (progn (goto-char startp)                         (nil-to-point-min (search-backward "\n" 0 0 1))))
      (setq nextcomment   (progn (goto-char bol)                            (nil-to-point-max (search-forward *inferior-zjulia-comment-char* nil 0 1))))
      (setq eol           (progn (goto-char startp)                         (nil-to-point-max (search-forward "\n" nil 0 1))))

      ;; start from eol, or from nextcomment if nextcomment is < eol
      (setq start-backwards-search eol)
      (when (< nextcomment eol)
	(setq start-backwards-search nextcomment))

      (setq next-word-back 
	    (progn 
	      (goto-char start-backwards-search)    
	      (+ 
	       (point) 
	       (skip-chars-backward "\t ;\n"))))

      (goto-char next-word-back)
)))


;;; provide ourself


(provide 'zjulia-mode)

