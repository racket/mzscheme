
(lambda (request failure)
  (case request
    [(name) "mzc"]
    [(compile-prefix) '(begin
			 (require-library "refer.ss")
			 (require-library "sigload.ss" "compiler"))]
    [(compile-omit-files) 
     (list "sig.ss" "sigload.ss" "compile-plt.ss")]
    [(mzscheme-launcher-libraries) (list "start.ss" "compile-plt.ss")]
    [(mzscheme-launcher-names) (list "mzc" "Compile PLT")]
    [else (failure)]))
