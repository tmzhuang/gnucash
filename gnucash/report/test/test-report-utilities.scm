(use-modules (gnucash gnc-module))

(gnc:module-begin-syntax (gnc:module-load "gnucash/app-utils" 0))
(gnc:module-begin-syntax (gnc:module-load "gnucash/report" 0))

(use-modules (srfi srfi-64))
(use-modules (tests srfi64-extras))
(use-modules (tests test-engine-extras))
(use-modules (tests test-report-extras))
(use-modules (gnucash report))

(setlocale LC_ALL "C")

(define (run-test)
  (test-runner-factory gnc:test-runner)
  (test-begin "report-utilities")
  (test-account-get-trans-type-splits-interval)
  (test-list-ref-safe)
  (test-list-set-safe)
  (test-gnc-pk)
  (test-gnc:monetary->string)
  (test-commodity-collector)
  (test-get-account-balances)
  (test-monetary-adders)
  (test-utility-functions)
  (test-end "report-utilities"))

(define (NDayDelta t64 n)
  (let* ((day-secs (* 60 60 24 n)) ; n days in seconds is n times 60 sec/min * 60 min/h * 24 h/day
         (new-secs (- t64 day-secs)))
    new-secs))

(define (collector->list coll)
  ;; input:  collector
  ;; output: list of monetary pairs e.g. '(("USD" . 25) ("GBP" . 15.00))
  (define (monetary->pair comm amt)
    (cons (gnc-commodity-get-mnemonic comm) amt))
  (append (coll 'format monetary->pair #f)))

(define (test-account-get-trans-type-splits-interval)
  (test-group-with-cleanup "test-account-get-trans-type-splits-interval"
  (let* ((env (create-test-env))
         (ts-now (gnc-localtime (current-time)))
         (test-day (tm:mday ts-now))
         (test-month (+ 1 (tm:mon ts-now)))
         (test-year (+ 1900 (tm:year ts-now)))
         (end-date (gnc-dmy2time64-neutral test-day test-month test-year))
         (start-date (NDayDelta end-date 10))
         (q-end-date (gnc-dmy2time64-end test-day test-month test-year))
         (q-start-date (gnc-dmy2time64 test-day test-month test-year))
         (q-start-date (NDayDelta q-start-date 5)))

    (let* ((accounts (env-create-account-structure-alist env (list "Assets"
								   (list (cons 'type ACCT-TYPE-ASSET))
								   (list "Bank Account")
								   (list "Wallet"))))
	   (bank-account (cdr (assoc "Bank Account" accounts)))
	   (wallet (cdr (assoc "Wallet" accounts))))

      (env-create-daily-transactions env start-date end-date bank-account wallet)
      (format #t "Created transactions for each day from ~a to ~a~%" (gnc-ctime start-date) (gnc-ctime end-date))
      (let ((splits (gnc:account-get-trans-type-splits-interval (list bank-account wallet)
							      ACCT-TYPE-ASSET
							      q-start-date q-end-date)))
	;; 10 is the right number (5 days, two splits per tx)
	(test-equal "length splits = 10"
          10
          (length splits)))))
  (teardown)))

(define (teardown)
  (gnc-clear-current-session))

(define (test-list-ref-safe)
  (test-begin "list-ref-safe")
  (let ((lst '(1 2)))
    (test-equal "list-ref-safe normal"
      1
      (list-ref-safe lst 0))
    (test-equal "list-ref-safe out of bounds"
      #f
      (list-ref-safe lst 3)))
  (test-end "list-ref-safe"))

(define (test-list-set-safe)
  (test-begin "list-set-safe")
  (let ((lst (list 1 2)))
    (list-set-safe! lst 1 3)
    (test-equal "list-set-safe normal"
      '(1 3)
      lst)
    (list-set-safe! lst 5 1)
    (test-equal "list-set-safe out-of-bounds"
      '(1 3 #f #f #f 1)
      lst))
  (test-end "list-set-safe"))

(define (test-gnc:monetary->string)
  (test-group-with-cleanup "gnc:monetary->string"
    (let* ((book (gnc-get-current-book))
           (comm-table (gnc-commodity-table-get-table book))
           (monetary (gnc:make-gnc-monetary
                      (gnc-commodity-table-lookup comm-table "CURRENCY" "USD")
                      100)))
      (test-assert "gnc:monetary->string is a string"
        (string? (gnc:monetary->string monetary))))
    (teardown)))

(define (test-gnc-pk)
  (test-begin "debugging tools")
  (test-equal "gnc:pk testing"
    'works
    (gnc:pk 'testing "gnc:pk" 'works))
  (test-equal "gnc:strify #t"
    "#t"
    (gnc:strify #t))
  (test-equal "gnc:strify '()"
    "#null"
    (gnc:strify '()))
  (test-equal "gnc:strify 'sym"
    "'sym"
    (gnc:strify 'sym))
  (test-equal "gnc:strify \"str\""
    "str"
    (gnc:strify "str"))
  (test-equal "gnc:strify '(1 2 3)"
    "(list 1 2 3)"
    (gnc:strify '(1 2 3)))
  (test-equal "gnc:strify (a . 2)"
    "('a . 2)"
    (gnc:strify (cons 'a 2)))
  (test-equal "gnc:strify cons"
    "Proc<identity>"
    (gnc:strify identity))
  (let ((coll (gnc:make-commodity-collector)))
    (test-equal "gnc:strify <mon-coll>"
      "coll<()>"
      (gnc:strify coll))
    (coll 'add (gnc-commodity-table-lookup
                (gnc-commodity-table-get-table
                 (gnc-get-current-book)) "CURRENCY" "USD") 10)
    (test-equal "gnc:strify <mon-coll $10>"
      "coll<([$10.00])>"
      (gnc:strify coll)))
  (let ((coll (gnc:make-value-collector)))
    (test-equal "gnc:strify <val-coll 0>"
      "coll<0>"
      (gnc:strify coll))
    (coll 'add 10)
    (test-equal "gnc:strify <val-coll 10>"
      "coll<10>"
      (gnc:strify coll)))
  (test-end "debugging tools"))

(define (test-commodity-collector)
  (test-group-with-cleanup "test-commodity-collector"
    (let* ((book (gnc-get-current-book))
           (comm-table (gnc-commodity-table-get-table book))
           (USD (gnc-commodity-table-lookup comm-table "CURRENCY" "USD"))
           (GBP (gnc-commodity-table-lookup comm-table "CURRENCY" "GBP"))
           (EUR (gnc-commodity-table-lookup comm-table "CURRENCY" "EUR"))
           (coll-A (gnc:make-commodity-collector))
           (coll-B (gnc:make-commodity-collector)))

      (test-equal "commodity-collector empty"
        '()
        (collector->list coll-A))

      (coll-A 'add USD 25)
      (test-equal "coll-A 'add USD25"
        '(("USD" . 25))
        (collector->list coll-A))

      (coll-A 'add USD 25)
      (test-equal "coll-A 'add USD25"
        '(("USD" . 50))
        (collector->list coll-A))

      (coll-A 'add GBP 20)
      (test-equal "coll-A 'add GBP20"
        '(("GBP" . 20) ("USD" . 50))
        (collector->list coll-A))

      (coll-A 'reset #f #f)
      (test-equal "coll-A 'reset"
        '()
        (collector->list coll-A))

      (coll-A 'add USD 25)
      (coll-B 'add GBP 20)
      (test-equal "coll-B 'add GBP20"
        '(("GBP" . 20))
        (collector->list coll-B))

      (coll-A 'merge coll-B #f)
      (test-equal "coll-A 'merge coll-B"
        '(("GBP" . 20) ("USD" . 25))
        (collector->list coll-A))

      (coll-A 'reset #f #f)
      (coll-A 'add USD 25)
      (coll-A 'minusmerge coll-B #f)
      (test-equal "coll-A 'minusmerge coll-B"
        '(("GBP" . -20) ("USD" . 25))
        (collector->list coll-A))

      (test-equal "coll-A 'getpair USD"
        (list USD 25)
        (coll-A 'getpair USD #f))

      (test-equal "coll-A 'getmonetary USD"
        (gnc:make-gnc-monetary USD 25)
        (coll-A 'getmonetary USD #f))

      (test-equal "gnc:collector+"
        '(("USD" . 50) ("GBP" . -20))
        (collector->list
         (gnc:collector+ coll-A coll-A coll-B)))

      (test-equal "gnc:collector- 1 arg"
        '(("GBP" . 20) ("USD" . -25))
        (collector->list
         (gnc:collector- coll-A)))

      (test-equal "gnc:collector- 3 args"
        '(("USD" . 25) ("GBP" . -60))
        (collector->list
         (gnc:collector- coll-A coll-B coll-B)))

      (test-equal "gnc:commodity-collector-get-negated"
        '(("USD" . -25) ("GBP" . 20))
        (collector->list
         (gnc:commodity-collector-get-negated coll-A)))

      (test-equal "gnc-commodity-collector-allzero? #f"
        #f
        (gnc-commodity-collector-allzero? coll-A))

      ;; coll-A has -GBP20 and USD25 for now, bring bal to 0 each
      (coll-A 'add GBP 20)
      (coll-A 'add USD -25)
      (test-equal "gnc-commodity-collector-allzero? #t"
        #t
        (gnc-commodity-collector-allzero? coll-A)))
    (teardown)))

(define (mnemonic->commodity sym)
  (gnc-commodity-table-lookup
   (gnc-commodity-table-get-table (gnc-get-current-book))
   (gnc-commodity-get-namespace (gnc-default-report-currency))
   sym))

(define (structure)
  (list "Root" (list (cons 'type ACCT-TYPE-ASSET))
        (list "Asset"
              (list "Bank")
              (list "GBP Bank" (list (cons 'commodity (mnemonic->commodity "GBP")))
                    (list "GBP Savings"))
              (list "Wallet"))
        (list "Income" (list (cons 'type ACCT-TYPE-INCOME)))
        (list "Income-GBP" (list (cons 'type ACCT-TYPE-INCOME)
                                 (cons 'commodity (mnemonic->commodity "GBP"))))
        (list "Expenses" (list (cons 'type ACCT-TYPE-EXPENSE))
              (list "Fuel"))
        (list "Liabilities" (list (cons 'type ACCT-TYPE-LIABILITY)))
        (list "Equity" (list (cons 'type ACCT-TYPE-EQUITY)))
        ))

(define (create-test-data)
  (let* ((env (create-test-env))
         (account-alist (env-create-account-structure-alist env (structure)))
         (asset (cdr (assoc "Asset" account-alist)))
         (bank (cdr (assoc "Bank" account-alist)))
         (gbp-bank (cdr (assoc "GBP Bank" account-alist)))
         (gbp-savings (cdr (assoc "GBP Savings" account-alist)))
         (wallet (cdr (assoc "Wallet" account-alist)))
         (income (cdr (assoc "Income" account-alist)))
         (gbp-income (cdr (assoc "Income-GBP" account-alist)))
         (expense (cdr (assoc "Expenses" account-alist)))
         (liability (cdr (assoc "Liabilities" account-alist)))
         (equity (cdr (assoc "Equity" account-alist))))
    ;; populate datafile with old transactions
    (env-transfer env 01 01 1970 bank expense       5   #:description "desc-1" #:num "trn1" #:memo "memo-3")
    (env-transfer env 31 12 1969 income bank       10   #:description "desc-2" #:num "trn2" #:void-reason "void" #:notes "notes3")
    (env-transfer env 31 12 1969 income bank       29   #:description "desc-3" #:num "trn3"
                  #:reconcile (cons #\c (gnc-dmy2time64 01 03 1970)))
    (env-transfer env 01 02 1970 bank expense      15   #:description "desc-4" #:num "trn4" #:notes "notes2" #:memo "memo-1")
    (env-transfer env 10 01 1970 liability expense 10   #:description "desc-5" #:num "trn5" #:void-reason "any")
    (env-transfer env 10 01 1970 liability expense 11   #:description "desc-6" #:num "trn6" #:notes "notes1")
    (env-transfer env 10 02 1970 bank liability     8   #:description "desc-7" #:num "trn7" #:notes "notes1" #:memo "memo-2"
                  #:reconcile (cons #\y (gnc-dmy2time64 01 03 1970)))
    (env-transfer env 01 01 1975 equity asset      15  #:description "$15 in asset")
    (env-transfer-foreign env 15 01 2000 gbp-bank bank 10 14 #:description "GBP 10 to USD 14")
    (env-transfer-foreign env 15 02 2000 bank gbp-bank  9  6 #:description "USD 9 to GBP 6")
    (env-transfer env 15 03 2000 gbp-bank gbp-savings 5 #:description "GBP 5 from bank to savings")
    ;; A single closing transaction
    (let ((closing-txn (env-transfer env 31 12 1999 expense equity 111 #:description "Closing")))
      (xaccTransSetIsClosingTxn closing-txn #t))
    (for-each (lambda (m)
                (env-transfer env 08 (1+ m) 1978 gbp-income gbp-bank 51 #:description "#51 income")
                (env-transfer env 03 (1+ m) 1978 income bank  103 #:description "$103 income")
                (env-transfer env 15 (1+ m) 1978 bank expense  22 #:description "$22 expense")
                (env-transfer env 09 (1+ m) 1978 income bank  109 #:description "$109 income"))
              (iota 12))
    (let ((mid (floor (/ (+ (gnc-accounting-period-fiscal-start)
                            (gnc-accounting-period-fiscal-end)) 2))))
      (env-create-transaction env mid bank income 200))))


(define (test-get-account-balances)
  (define (account-lookup str)
    (gnc-account-lookup-by-name
     (gnc-book-get-root-account (gnc-get-current-book))
     str))

  (create-test-data)

  (test-group-with-cleanup "test-get-account-balances"
    (let* ((all-accounts (gnc-account-get-descendants
                          (gnc-book-get-root-account (gnc-get-current-book))))
           (asset (account-lookup "Asset"))
           (expense (account-lookup "Expenses"))
           (income (account-lookup "Income"))
           (bank (account-lookup "Bank"))
           (gbp-bank (account-lookup "GBP Bank")))

      (test-equal "gnc:account-get-comm-balance-at-date 1/1/2001 incl children"
        '(("GBP" . 608) ("USD" . 2301))
        (collector->list
         (gnc:account-get-comm-balance-at-date asset (gnc-dmy2time64 01 01 2001) #t)))

      (test-equal "gnc:account-get-comm-balance-at-date 1/1/2001 excl children"
        '(("USD" . 15))
        (collector->list
         (gnc:account-get-comm-balance-at-date asset (gnc-dmy2time64 01 01 2001) #f)))

      (test-equal "gnc:account-get-comm-value-interval 1/1/2000-1/1/2001 excl children"
        '(("USD" . 9) ("GBP" . -15))
        (collector->list
         (gnc:account-get-comm-value-interval gbp-bank
                                              (gnc-dmy2time64 01 01 2000)
                                              (gnc-dmy2time64 01 01 2001)
                                              #f)))

      (test-equal "gnc:account-get-comm-value-interval 1/1/2000-1/1/2001 incl children"
        '(("USD" . 9) ("GBP" . -10))
        (collector->list
         (gnc:account-get-comm-value-interval gbp-bank
                                              (gnc-dmy2time64 01 01 2000)
                                              (gnc-dmy2time64 01 01 2001)
                                              #t)))

      (test-equal "gnc:account-get-comm-value-at-date 1/1/2001 excl children"
        '(("USD" . 9) ("GBP" . 597))
        (collector->list
         (gnc:account-get-comm-value-at-date gbp-bank
                                             (gnc-dmy2time64 01 01 2001)
                                             #f)))

      (test-equal "gnc:account-get-comm-value-at-date 1/1/2001 incl children"
        '(("USD" . 9) ("GBP" . 602))
        (collector->list
         (gnc:account-get-comm-value-at-date gbp-bank
                                             (gnc-dmy2time64 01 01 2001)
                                             #t)))

      (test-equal "gnc:accounts-get-comm-total-profit"
        '(("GBP" . 612) ("USD" . 2389))
        (collector->list
         (gnc:accounts-get-comm-total-profit all-accounts
                                             (lambda (acct)
                                               (gnc:account-get-comm-balance-at-date
                                                acct (gnc-dmy2time64 01 01 2001) #f)))))

      (test-equal "gnc:accounts-get-comm-total-income"
        '(("GBP" . 612) ("USD" . 2573))
        (collector->list
         (gnc:accounts-get-comm-total-income all-accounts
                                             (lambda (acct)
                                               (gnc:account-get-comm-balance-at-date
                                                acct (gnc-dmy2time64 01 01 2001) #f)))))

      (test-equal "gnc:accounts-get-comm-total-expense"
        '(("USD" . -184))
        (collector->list
         (gnc:accounts-get-comm-total-expense all-accounts
                                              (lambda (acct)
                                                (gnc:account-get-comm-balance-at-date
                                                 acct (gnc-dmy2time64 01 01 2001) #f)))))

      (test-equal "gnc:accounts-get-comm-total-assets"
        '(("GBP" . 608) ("USD" . 2394))
        (collector->list
         (gnc:accounts-get-comm-total-assets all-accounts
                                             (lambda (acct)
                                               (gnc:account-get-comm-balance-at-date
                                                acct (gnc-dmy2time64 01 01 2001) #f)))))

      (test-equal "gnc:account-get-balance-interval 1/1/60 - 1/1/01 incl children"
        608
        (gnc:account-get-balance-interval gbp-bank
                                          (gnc-dmy2time64 01 01 1960)
                                          (gnc-dmy2time64 01 01 2001)
                                          #t))

      (test-equal "gnc:account-get-balance-interval 1/1/60 - 1/1/01 excl children"
        603
        (gnc:account-get-balance-interval gbp-bank
                                          (gnc-dmy2time64 01 01 1960)
                                          (gnc-dmy2time64 01 01 2001)
                                          #f))

      (test-equal "gnc:account-comm-balance-interval 1/1/1960-1/1/2001 incl children"
        '(("GBP" . 608))
        (collector->list
         (gnc:account-get-comm-balance-interval gbp-bank
                                                (gnc-dmy2time64 01 01 1960)
                                                (gnc-dmy2time64 01 01 2001)
                                                #t)))

      (test-equal "gnc:account-comm-balance-interval 1/1/1960-1/1/2001 excl children"
        '(("GBP" . 603))
        (collector->list
         (gnc:account-get-comm-balance-interval gbp-bank
                                                (gnc-dmy2time64 01 01 1960)
                                                (gnc-dmy2time64 01 01 2001)
                                                #f)))

      (test-equal "gnc:accountlist-get-comm-balance-interval"
        '(("USD" . 279))
        (collector->list
         (gnc:accountlist-get-comm-balance-interval (list expense)
                                                    (gnc-dmy2time64 15 01 1970)
                                                    (gnc-dmy2time64 01 01 2001))))

      (test-equal "gnc:accountlist-get-comm-balance-interval-with-closing"
        '(("USD" . 168))
        (collector->list
         (gnc:accountlist-get-comm-balance-interval-with-closing (list expense)
                                                                 (gnc-dmy2time64 15 01 1970)
                                                                 (gnc-dmy2time64 01 01 2001))))

      (test-equal "gnc:accountlist-get-comm-balance-at-date"
        '(("USD" . 295))
        (collector->list
         (gnc:accountlist-get-comm-balance-at-date (list expense)
                                                   (gnc-dmy2time64 01 01 2001))))

      (test-equal "gnc:accountlist-get-comm-balance-interval-with-closing"
        '(("USD" . 184))
        (collector->list
         (gnc:accountlist-get-comm-balance-at-date-with-closing (list expense)
                                                                (gnc-dmy2time64 01 01 2001))))

      (test-equal "gnc:accounts-count-splits"
        44
        (gnc:accounts-count-splits (list expense income)))

      (let ((account-balances (gnc:get-assoc-account-balances
                               (list bank gbp-bank)
                               (lambda (acct)
                                 (gnc:account-get-comm-balance-at-date
                                  acct (gnc-dmy2time64 01 01 2001) #f)))))

        (test-equal "gnc:get-assoc-account-balances"
          '(("USD" . 2286))
          (collector->list (car (assoc-ref account-balances bank))))

        (test-equal "gnc:select-assoc-account-balance - hit"
          '(("USD" . 2286))
          (collector->list
           (gnc:select-assoc-account-balance account-balances bank)))

        (test-equal "gnc:select-assoc-account-balance - miss"
          #f
          (collector->list
           (gnc:select-assoc-account-balance account-balances expense)))

        (test-equal "gnc:get-assoc-account-balances-total"
          '(("GBP" . 603) ("USD" . 2286))
          (collector->list
           (gnc:get-assoc-account-balances-total account-balances)))))
    (teardown)))

(define (test-utility-functions)

  (define (account-lookup str)
    (gnc-account-lookup-by-name
     (gnc-book-get-root-account (gnc-get-current-book))
     str))

  (test-group-with-cleanup "utility functions"
    (create-test-data)
    (test-equal "gnc:accounts-get-commodities"
      (list "GBP" "USD")
      (map gnc-commodity-get-mnemonic
           (gnc:accounts-get-commodities (gnc-account-get-descendants-sorted
                                          (gnc-get-current-root-account))
                                         #f)))

    (test-equal "gnc:get-current-account-tree-depth"
      5
      (gnc:get-current-account-tree-depth))

    (test-equal "gnc:accounts-and-all-descendants"
      (list (account-lookup "GBP Bank")
            (account-lookup "GBP Savings")
            (account-lookup "Expenses")
            (account-lookup "Fuel"))
      (gnc:accounts-and-all-descendants
       (list (account-lookup "Expenses")
             (account-lookup "GBP Bank"))))

    (teardown)))

(define (test-monetary-adders)
  (define (monetary->pair mon)
    (let ((comm (gnc:gnc-monetary-commodity mon))
          (amt (gnc:gnc-monetary-amount mon)))
      (cons (gnc-commodity-get-mnemonic comm) amt)))
  (let* ((book (gnc-get-current-book))
         (comm-table (gnc-commodity-table-get-table book))
         (USD (gnc-commodity-table-lookup comm-table "CURRENCY" "USD"))
         (GBP (gnc-commodity-table-lookup comm-table "CURRENCY" "GBP"))
         (EUR (gnc-commodity-table-lookup comm-table "CURRENCY" "EUR"))
         (usd10 (gnc:make-gnc-monetary USD 10))
         (usd8 (gnc:make-gnc-monetary USD 8))
         (gbp10 (gnc:make-gnc-monetary GBP 10))
         (gbp8 (gnc:make-gnc-monetary GBP 8))
         (eur10 (gnc:make-gnc-monetary EUR 10))
         (eur8 (gnc:make-gnc-monetary EUR 8)))

    (test-equal "gnc:monetaries-add 1 currency"
      '(("USD" . 20))
      (collector->list
       (gnc:monetaries-add usd10 usd10)))

    (test-equal "gnc:monetaries-add 2 currencies"
      '(("GBP" . 8) ("USD" . 10))
      (collector->list
       (gnc:monetaries-add usd10 gbp8)))

    (test-equal "gnc:monetaries-add 3 currencies"
      '(("EUR" . 8) ("GBP" . 8) ("USD" . 20))
      (collector->list
       (gnc:monetaries-add usd10 gbp8 eur8 usd10)))

    (test-equal "gnc:monetary+ with 1 currency succeeds"
      '("USD" . 28)
      (monetary->pair
       (gnc:monetary+ usd10 usd10 usd8)))

    (test-error
     "gnc:monetary+ with >1 currency fails"
     #t
     (gnc:monetary+ usd10 usd10 eur8))))
