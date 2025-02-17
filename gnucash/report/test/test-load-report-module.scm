(debug-enable 'backtrace)

(debug-set! stack 500000)

(display "  testing report module load ... ")
(setenv "GNC_UNINSTALLED" "1")
(use-modules (gnucash gnc-module))

(gnc:module-system-init)

(if (gnc:module-load "gnucash/report" 0)
    (begin 
      (display "ok\n")
      (exit 0))
    (begin 
      (display "failed\n")
      (exit -1)))
