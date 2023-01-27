(in-package #:clim-internals)

;;;
;;; TEXT-EDITING-GADGET implements all behavior (and initargs) expected from
;;; TEXT-FIELD-PANE and TEXT-EDITOR-PANE. Both classes differ by default
;;; initarg values (i.e TEXT-FIELD-PANE does not allow line breaks).
;;;
;;; TODO ("nice to have" extensions)
;;;
;;;   (end-of-line-action :initarg :end-of-line-action)
;;;   (end-of-page-action :initarg :end-of-page-action)
;;;

(defclass text-editing-gadget (edward-mixin text-editor)
  ((allow-line-breaks :initarg :allow-line-breaks) ; single line?
   (gadget-resizeable :initarg :gadget-resizeable) ; truncate output?
   (activation-gestures :accessor activation-gestures
                        :initarg :activation-gestures)
   (text-cursor :accessor stream-text-cursor))
  (:default-initargs :foreground +black+
                     :background +white+
                     :allow-line-breaks t
                     :gadget-resizeable nil
                     :activation-gestures '()))

(defmethod ie-insert-newline :around
    ((sheet text-editing-gadget) buffer event numarg)
  (if (slot-value sheet 'allow-line-breaks)
      (call-next-method)
      (beep sheet)))

(defmethod ie-insert-newline-after-cursor :around
    ((sheet text-editing-gadget) buffer event numarg)
  (if (slot-value sheet 'allow-line-breaks)
      (call-next-method)
      (beep sheet)))

(defmethod initialize-instance :after ((gadget text-editing-gadget) &key value)
  (setf (gadget-value gadget) value)
  (with-sheet-medium (medium gadget)
    (let* ((ts (medium-text-style medium))
           (ht (text-style-height ts medium))
           (editable (editable-p gadget)))
      (setf (stream-text-cursor gadget)
            (make-instance 'standard-text-cursor :sheet gadget
                                                 :width 2
                                                 :height ht
                                                 :visibility editable)))))

(defmethod (setf editable-p) :after (new-value (object text-editing-gadget))
  (setf (cursor-visibility (stream-text-cursor object)) new-value))

(defmethod gadget-value ((sheet text-editing-gadget))
  (edward-buffer-string (input-editor-buffer sheet)))

(defmethod (setf gadget-value) (new-value (sheet text-editing-gadget) &rest args)
  (declare (ignore args))
  (ie-clear-input-buffer sheet (input-editor-buffer sheet) nil 1)
  (loop for ch across new-value do
    (handle-editor-event sheet ch))
  (dispatch-repaint sheet +everywhere+))

(defmethod handle-event :around ((sheet text-editing-gadget) event)
  (with-activation-gestures ((activation-gestures sheet) :override t)
    (if (activation-gesture-p event)
        (activate-callback sheet (gadget-client sheet) (gadget-id sheet))
        (call-next-method))))

(defmethod handle-event ((sheet text-editing-gadget) (event key-press-event))
  (if (and (editable-p sheet)
           (handle-editor-event sheet event))
      (progn
        (when (slot-value sheet 'gadget-resizeable)
          (change-space-requirements sheet))
        (dispatch-repaint sheet +everywhere+))
      (call-next-method)))

(defmethod handle-event ((sheet text-editing-gadget) (event pointer-event))
  (if (and (editable-p sheet)
           (handle-editor-event sheet event))
      (dispatch-repaint sheet +everywhere+)
      (call-next-method)))

(defmethod handle-event ((sheet text-editing-gadget)
                         (event window-manager-focus-event))
  (when (editable-p sheet)
    (stream-set-input-focus sheet)))

(defmethod note-input-focus-changed ((sheet text-editing-gadget) state)
  (dispatch-repaint sheet +everywhere+))

(defmethod handle-repaint ((sheet text-editing-gadget) region)
  (with-sheet-medium (medium sheet)
    (let* ((text-cursor (stream-text-cursor sheet))
           (line-height (cursor-height text-cursor))
           (cursor (edward-cursor sheet))
           (cursor-line (cluffer:line cursor))
           (cursor-position (cluffer:cursor-position cursor))
           (current-y 0))
      (flet ((draw-line (line)
               (let ((text (edward-line-string line)))
                 ;; Update the cursor.
                 (when (and (eq line cursor-line)
                            (cursor-active text-cursor))
                   (let ((current-x (nth-value 2 (text-size medium text :end cursor-position))))
                     (setf (cursor-position text-cursor)
                           (values current-x current-y))))
                 ;; Draw the line.
                 (draw-text* sheet text 0 current-y :align-x :left :align-y :top)
                 ;; Increment the drawing position.
                 (incf current-y line-height))))
        (declare (dynamic-extent (function draw-line)))
        (edward-map-over-lines (input-editor-buffer sheet) #'draw-line)
        (draw-design sheet text-cursor)))))

(defmethod compose-space ((sheet text-editing-gadget) &key width height)
  (declare (ignore width height))
  (multiple-value-bind (buffer-w buffer-h)
      (edward-buffer-extent sheet)
    (with-sheet-medium (medium sheet)
      (let* ((text-style (medium-text-style medium))
             (ts-w (text-style-width text-style medium))
             (ts-h (text-style-height text-style medium))
             (min-w (* ts-w (text-editor-ncolumns sheet)))
	     (min-h (* ts-h (text-editor-nlines sheet))))
        (when (slot-value sheet 'gadget-resizeable)
          (setf buffer-w (maxf min-w buffer-w))
          (setf buffer-h (maxf min-h buffer-h)))
        (make-space-requirement :min-width min-w :min-height min-h
                                :width buffer-w :height buffer-h)))))

(defclass text-field-pane (text-editing-gadget)
  ()
  (:default-initargs :nlines 1
                     :ncolumns 20
                     ;; :end-of-line-action :scroll
                     :allow-line-breaks nil
                     :activation-gestures *standard-activation-gestures*))

(defclass text-editor-pane (text-editing-gadget)
  ()
  (:default-initargs :nlines 6
                     :ncolumns 20
                     ;; :end-of-line-action :wrap*
   ))
