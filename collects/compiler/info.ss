
(lambda (request)
  (case request
    [(name) "mzc"]
    [(compile-prefix) '(begin
			 (require-library "refer.ss")
			 (require-library "sigload.ss" "compiler"))]
    [(compile-omit-files) 
     (list "sig.ss" "sigload.ss")]
    [else (error 'mzc-info "Unknown request: ~s" request)]))
