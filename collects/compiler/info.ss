
(let ([spidey? (with-handlers ([void (lambda (x) #f)])
		 (collection-path "mrspidey"))])
  (lambda (request failure)
    (case request
      [(name) "mzc"]
      [(compile-prefix) `(begin
			   (read-case-sensitive #t)
			   (require-library "refer.ss")
			   (require-library "setupsig.ss" "compiler")
			   ,(if spidey?
				`(require-library "spsigload.ss" "compiler")
				`(require-library "sigload.ss" "compiler")))]
      [(compile-omit-files) 
       (list* "sig.ss" "sigload.ss" "spsigload.ss" "setup.ss" "setupsig.ss"
	      (if spidey?
		  null
		  (list "sploadr.ss" "mrspideyi.ss" "mrspidey.ss")))]
      [(compile-elaboration-zos) (list "sig.ss" "sigload.ss" "setupsig.ss")]
      [(mzscheme-launcher-libraries) (list "start.ss" "setup.ss")]
      [(mzscheme-launcher-names) (list "mzc" "Setup PLT")]
      [else (failure)])))
