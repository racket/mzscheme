
(module info (lib "infotab.ss" "setup")
  (define name "mzc")

  (define mzscheme-launcher-libraries (list "start.ss"))
  (define mzscheme-launcher-names (list "mzc"))

  (define compile-omit-files
    '("mrspidey.ss" "mrspideyf.ss" "mrspideyi.ss" "embedr.ss")))
