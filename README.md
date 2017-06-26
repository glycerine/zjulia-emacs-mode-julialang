# zjulia-emacs-mode-julialang

zjulia.el is an emacs mode for julia (julialang) that lets one step through code, line-by-line, with a single keypress.

I first learned the utility of this ability to single-step through scripts from ESS. I don't know how people get anything done without this kind of functionality.


# install

~~~
 how to install:

 (1) If you are changing which interpreter you want to use, examine
     and adjust the "commonly-adjusted parameters" section just below.

 (2) Copy zjulia-mode.el into your ~/.emacs.d/  directory.

 (3) Then put this in your .emacs:

    (load "/home/jaten/.emacs.d/zjulia.el") ; adjust path to fit your home directory.
    (require 'zjulia-mode)
    (global-set-key "\C-n" 'zjulia-send-line)

 (4) Optionally for speed, M-x byte-compile-file <enter> 
                           ~/.emacs.d/zjulia.el <enter>

 (5) To use, do 'M-x run-zjulia' to start the interpreter. Open
     your script and in the script buffer do 'M-x zjulia-mode'.

     Or, open a file with an automatically recognized extension
     (as specified below) and press 'C-n' on the first line
     you want executed in the interpreter.
~~~

# License
~~~
              This minimal pair of (major and inferior) modes
              was derived from the Emacs Octave Support modes in 
              octave-mod.el and octave-inf.el, with a little help 
              (and alot of inspiration) from the ess-mode.el for
              R. As such it falls under the GNU General Public
              License version 3 or later. The GPL applies solely
              to this single file and does not apply to any
              other files distributed here.
~~~

Copyright (C) 2017, Author: Jason E. Aten, Ph.D.
