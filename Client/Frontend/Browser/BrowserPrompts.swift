/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Shared

@objc protocol JSPromptAlertControllerDelegate: class {
    func promptAlertControllerDidDismiss(_ alertController: JSPromptAlertController)
}

/// A simple version of UIViewController (previously- UIAlertController) that attaches a delegate to the viewDidDisappear method
/// to allow forwarding the event. The reason this is needed for prompts from Javascript is we
/// need to invoke the completionHandler passed to us from the WKWebView delegate or else
/// a runtime exception is thrown. This new implementation creates a custom Alert that does not block the window and make app prone to JS DOS Attacks such as alerts in loop.
class JSPromptAlertController: UIViewController {
    var alertInfo: JSAlertInfo?

    weak var delegate: JSPromptAlertControllerDelegate?
    
    private var _title: String?
    private var _message: String?
    private var _style: UIAlertController.Style!
    
    private lazy var _scrollView: UIScrollView = {
        let scroll: UIScrollView = UIScrollView(frame: CGRect(size: self.view.frame.size))
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        scroll.bounces = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0)
            ])
        return scroll
    }()
    
    private lazy var alertView: UIView = {
        let alert: UIView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        _scrollView.addSubview(alert)
        alert.backgroundColor = UIColor.white
        alert.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            alert.leadingAnchor.constraint(equalTo: _scrollView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            alert.trailingAnchor.constraint(equalTo: _scrollView.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            alert.bottomAnchor.constraint(equalTo: _scrollView.contentLayoutGuide.bottomAnchor, constant: 0),
            alert.centerYAnchor.constraint(equalTo: _scrollView.centerYAnchor),
            alert.centerXAnchor.constraint(equalTo: _scrollView.centerXAnchor)
            ])
        alert.layer.cornerRadius = 5.0
        alert.layer.masksToBounds = true
        alert.clipsToBounds = true
        return alert
    }()
    
    private lazy var mainStackView: UIStackView = {
        let stack: UIStackView = UIStackView(arrangedSubviews: [])
        stack.alignment = UIStackViewAlignment.fill
        stack.distribution = .fill
        stack.spacing = 8.0
        stack.axis = .vertical
        alertView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: alertView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: alertView.topAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: alertView.centerYAnchor),
            stack.bottomAnchor.constraint(equalTo: alertView.bottomAnchor, constant: -10)
            ])
        return stack
    }()
    
    private lazy var titleLabel: UILabel = {
        let label: UILabel = UILabel(frame: CGRect(x: 0, y: 0, width: 100.0, height: 30.0))
        label.font = UIFont.boldSystemFont(ofSize: 16.0)
        label.textColor = UIColor.black
        label.numberOfLines = 3
        label.textAlignment = .center
        mainStackView.addArrangedSubview(label)
        return label
    }()
    
    private lazy var messageLabel: UILabel = {
        let label: UILabel = UILabel(frame: CGRect(x: 0, y: 0, width: 100.0, height: 30.0))
        label.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = UIColor.black
        label.textAlignment = .center
        label.numberOfLines = 0
        mainStackView.addArrangedSubview(label)
        return label
    }()
    
    private var _textFields: [UITextField]?
    private var _actions: [(UIButton, JSAlertAction)]
    private lazy var actionStackView: UIStackView! = {
        let stack: UIStackView = UIStackView(arrangedSubviews: [])
        stack.alignment = UIStackViewAlignment.center
        stack.distribution = .fillEqually
        stack.spacing = 0.0
        stack.axis = .horizontal
        mainStackView.addArrangedSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        //        NSLayoutConstraint.activate([
        //            stack.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: 10),
        //            stack.trailingAnchor.constraint(equalTo: alertView.trailingAnchor, constant: -10),
        //            stack.topAnchor.constraint(equalTo: alertView.topAnchor, constant: 10),
        //            stack.centerYAnchor.constraint(equalTo: alertView.centerYAnchor),
        //            stack.bottomAnchor.constraint(equalTo: alertView.bottomAnchor, constant: -10)
        //            ])
        return stack
    }()
    
    private var topConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    
    private var presentAnimated: Bool = true
    
    private init() {
        _actions = []
        super.init(nibName: nil, bundle: nil)
    }
    
    public convenience init(title: String?, message: String?, preferredStyle: UIAlertController.Style) {
        self.init()
        _title = title
        _message = message
        _style = preferredStyle
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        registerForKeyboardNotifications()
        view.backgroundColor = UIColor.gray.withAlphaComponent(0.7)
        _title != nil ? titleLabel.text = _title : nil
        _message != nil ? messageLabel.text = _message : nil
        _scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 64, right: 0)
        textFields?.forEach(mainStackView.addArrangedSubview(_:))
        _actions.map({$0.0}).forEach(actionStackView.addArrangedSubview(_:))
        alertView.sizeToFit()
        if presentAnimated {
            alertView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            alertView.center = _scrollView.center
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if presentAnimated {
            UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseInOut], animations: {
                self.alertView.transform = .identity
                self.alertView.center = self._scrollView.center
            }, completion: nil)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        delegate?.promptAlertControllerDidDismiss(self)
    }
    
    func present(in controller: UIViewController, view: UIView, animated: Bool) {
        controller.addChildViewController(self)
        self.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self.view)
        // This will end editing(Dismiss any input view) to show the alert.
        view.endEditing(true)
        
        leadingConstraint = self.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0)
        trailingConstraint = self.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0)
        topConstraint = self.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 0)
        bottomConstraint = self.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0)
        
        NSLayoutConstraint.activate([
            topConstraint,
            bottomConstraint,
            leadingConstraint,
            trailingConstraint
            ])
        
        self.didMove(toParentViewController: controller)
        self.presentAnimated = animated
    }
    
    func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardAppear(_:)), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardDisappear(_:)), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    @objc func onKeyboardAppear(_ notification: NSNotification) {
        let info = notification.userInfo!
        if let rect: CGRect = info[UIKeyboardFrameEndUserInfoKey] as? CGRect,
            let animationDuration = info[UIKeyboardAnimationDurationUserInfoKey] as? TimeInterval {
            let kbSize = rect.size
            let animationCurve = UIViewAnimationOptions(rawValue: info[UIKeyboardAnimationCurveUserInfoKey] as? UInt ?? 0)
            
            let insets = UIEdgeInsets(top: 0, left: 0, bottom: kbSize.height, right: 0)
            _scrollView.contentInset = insets
            _scrollView.scrollIndicatorInsets = insets
            
            if let activeTextField: UITextField = _textFields?.filter({$0.isFirstResponder}).first {
                let textFieldRect: CGRect = mainStackView.convert(activeTextField.frame, to: self._scrollView)
                UIView.animate(withDuration: animationDuration, delay: 0.0, options: animationCurve, animations: {
                    self._scrollView.contentOffset = CGPoint(x: self._scrollView.contentOffset.x, y: textFieldRect.origin.y + textFieldRect.height + 20.0 - kbSize.height)
                }, completion: nil)
            }
        }
    }
    
    @objc func onKeyboardDisappear(_ notification: NSNotification) {
        _scrollView.contentInset = UIEdgeInsets.zero
        _scrollView.scrollIndicatorInsets = UIEdgeInsets.zero
    }
    
    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // update the constraints constant
        topConstraint.constant = 0
        bottomConstraint.constant = 0
        leadingConstraint.constant = 0
        trailingConstraint.constant = 0
    }
    
    open func addAction(_ action: JSAlertAction) {
        guard _actions.count < 3 else {
            return
        }
        let button: UIButton = UIButton(type: .roundedRect)
        button.setTitle(action.title, for: .normal)
        let color: UIColor
        let font: UIFont
        switch action.style! {
        case .cancel:
            color = UIColor.blue
            font = UIFont.systemFont(ofSize: 12, weight: .regular)
        case .destructive:
            color = UIColor.red
            font = UIFont.systemFont(ofSize: 14, weight: .regular)
        default:
            color = UIColor.blue
            font = UIFont.systemFont(ofSize: 12, weight: .regular)
        }
        button.setTitleColor(color, for: .normal)
        button.titleLabel?.font = font
        button.addTarget(self, action: #selector(actionPerformed(button:)), for: .touchUpInside)
        _actions.append((button, action))
    }
    
    @objc private func actionPerformed(button: UIButton) {
        if let action: JSAlertAction = _actions.filter({$0.0 === button}).first?.1 {
            action.handler?(action)
            self.removeFromParentViewController()
            self.view.removeFromSuperview()
        }
    }
    
    open var actions: [JSAlertAction] {
        get {
            return _actions.map({$0.1})
        }
    }
    
    open func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {
        //Add textfield here
        let textField: UITextField = UITextField(frame: CGRect(x: 0, y: 0, width: 0, height: 30.0))
        textField.borderStyle = .roundedRect
        textField.backgroundColor = UIColor.white
        _textFields == nil ? (_textFields = [textField]) : _textFields?.append(textField)
        configurationHandler?(textField)
    }
    
    open var textFields: [UITextField]? {
        get {
            return _textFields
        }
    }
}

open class JSAlertAction: NSObject {
    
    var handler: ((JSAlertAction) -> Void)?
    var style: UIAlertAction.Style!
    var title: String?
    
    init(title: String?, style: UIAlertAction.Style, handler: ((JSAlertAction) -> Void)? = nil) {
        super.init()
        self.title = title
        self.style = style
        self.handler = handler
    }
}

/**
 *  An JSAlertInfo is used to store information about an alert we want to show either immediately or later.
 *  Since alerts are generated by web pages and have no upper limit it would be unwise to allocate a
 *  UIAlertController instance for each generated prompt which could potentially be queued in the background.
 *  Instead, the JSAlertInfo structure retains the relevant data needed for the prompt along with a copy
 *  of the provided completionHandler to let us generate the UIAlertController when needed.
 */
protocol JSAlertInfo {
    func alertController() -> JSPromptAlertController
    func cancel()
}

struct MessageAlert: JSAlertInfo {
    let message: String
    let frame: WKFrameInfo
    let completionHandler: () -> Void

    func alertController() -> JSPromptAlertController {
        let alertController = JSPromptAlertController(title: titleForJavaScriptPanelInitiatedByFrame(frame),
            message: message,
            preferredStyle: .alert)
        alertController.addAction(JSAlertAction(title: Strings.OKString, style: .default) { _ in
            self.completionHandler()
        })
        alertController.alertInfo = self
        return alertController
    }

    func cancel() {
        completionHandler()
    }
}

struct ConfirmPanelAlert: JSAlertInfo {
    let message: String
    let frame: WKFrameInfo
    let completionHandler: (Bool) -> Void

    init(message: String, frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        self.message = message
        self.frame = frame
        self.completionHandler = completionHandler
    }

    func alertController() -> JSPromptAlertController {
        // Show JavaScript confirm dialogs.
        let alertController = JSPromptAlertController(title: titleForJavaScriptPanelInitiatedByFrame(frame), message: message, preferredStyle: .alert)
        alertController.addAction(JSAlertAction(title: Strings.OKString, style: .default) { _ in
            self.completionHandler(true)
        })
        alertController.addAction(JSAlertAction(title: Strings.CancelButtonTitle, style: .cancel) { _ in
            self.cancel()
        })
        alertController.alertInfo = self
        return alertController
    }

    func cancel() {
        completionHandler(false)
    }
}

struct TextInputAlert: JSAlertInfo {
    let message: String
    let frame: WKFrameInfo
    let completionHandler: (String?) -> Void
    let defaultText: String?

    var input: UITextField!

    init(message: String, frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void, defaultText: String?) {
        self.message = message
        self.frame = frame
        self.completionHandler = completionHandler
        self.defaultText = defaultText
    }

    func alertController() -> JSPromptAlertController {
        let alertController = JSPromptAlertController(title: titleForJavaScriptPanelInitiatedByFrame(frame), message: message, preferredStyle: .alert)
        var input: UITextField!
        alertController.addTextField(configurationHandler: { (textField: UITextField) in
            input = textField
            input.text = self.defaultText
        })
        alertController.addAction(JSAlertAction(title: Strings.OKString, style: .default) { _ in
            self.completionHandler(input.text)
        })
        alertController.addAction(JSAlertAction(title: Strings.CancelButtonTitle, style: .cancel) { _ in
            self.cancel()
        })
        alertController.alertInfo = self
        return alertController
    }

    func cancel() {
        completionHandler(nil)
    }
}

/// Show a title for a JavaScript Panel (alert) based on the WKFrameInfo. On iOS9 we will use the new securityOrigin
/// and on iOS 8 we will fall back to the request URL. If the request URL is nil, which happens for JavaScript pages,
/// we fall back to "JavaScript" as a title.
private func titleForJavaScriptPanelInitiatedByFrame(_ frame: WKFrameInfo) -> String {
    var title = "\(frame.securityOrigin.`protocol`)://\(frame.securityOrigin.host)"
    if frame.securityOrigin.port != 0 {
        title += ":\(frame.securityOrigin.port)"
    }
    return title
}
