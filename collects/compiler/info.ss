
(lambda (request failure)
  (case request
    [(name) "mzc"]
    [(compile-prefix) '(begin
			 (require-library "refer.ss")
			 (require-library "sigload.ss" "compiler"))]
    [(compile-omit-files) 
     (list "sig.ss" "sigload.ss" "compile-plt.ss")]
    [else (failure)]))
