
(let ([spidey? (with-handlers ([void (lambda (x) #f)])
		 (collection-path "mrspidey"))])
  (lambda (request failure)
    (case request
      [(name) "mzc"]
      [(compile-prefix) `(begin
			   (read-case-sensitive #t)
			   (require-library "refer.ss")
			   ,(if spidey?
				`(require-library "spsigload.ss" "compiler")
				`(require-library "sigload.ss" "compiler")))]
      [(compile-omit-files) 
       (list* "sig.ss" "sigload.ss" "spsigload.ss" "setup.ss"
	      (if spidey?
		  null
		  (list "sploadr.ss" "mrspideyi.ss" "mrspidey.ss")))]
      [(compile-extension-omit-files) (list "compiler.ss")]
      [(mzscheme-launcher-libraries) (list "start.ss" "setup.ss")]
      [(mzscheme-launcher-names) (list "mzc" "Setup PLT")]
      [else (failure)])))

