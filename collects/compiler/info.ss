

(module info (lib "infotab.ss" "setup")
  (define name "mzc")

  (define compile-omit-files
    '("

(let ([spidey? (with-handlers ([void (lambda (x) #f)])
		 (collection-path "mrspidey"))])
  (lambda (request failure)
    (case request
      [(name) "mzc"]
      [(compile-prefix) `(begin
			   (require-library "refer.ss")
			   ,(if spidey?
				`(require-library "spsigload.ss" "compiler")
				`(require-library "sigload.ss" "compiler")))]
      [(compile-omit-files) 
       (list* "sig.ss" "sigload.ss" "spsigload.ss"
	      (if spidey?
		  null
		  (list "sploadr.ss" "mrspideyi.ss" "mrspidey.ss" "mrspideyf.ss")))]
      [(compile-elaboration-zos) (list "sig.ss" "sigload.ss")]
      [(mzscheme-launcher-libraries) (list "start.ss")]
      [(mzscheme-launcher-names) (list "mzc")]
      [else (failure)])))
