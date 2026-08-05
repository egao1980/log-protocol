(defsystem "log-backend-log4cl"
  :version "0.1.1"
  :description "log-protocol backend using log4cl dependency"
  :author "egao1980"
  :license "MIT"
  :depends-on ("log-protocol" "log4cl")
  :serial t
  :pathname "src/backend-log4cl"
  :components ((:file "package")
               (:file "backend")))
