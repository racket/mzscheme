
(lambda (request failure)
  (case request
    [(name) "mzc"]
    [(compile-prefix) '(begin
			 (require-library "refer.ss")
			 (require-library "sigload.ss" "compiler"))]
    [(compile-omit-files) 
     (list "sig.ss" "sigload.ss" "setup.ss")]
    [(mzscheme-launcher-libraries) (list "start.ss" "setup.ss")]
    [(mzscheme-launcher-names) (list "mzc" "Setup PLT")]
    [else (failure)]))
