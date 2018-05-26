//
//  DocumentViewController.swift
//  Savanna iOS
//
//  Created by Louis D'hauwe on 30/12/2016.
//  Copyright © 2016 Silver Fox. All rights reserved.
//

import UIKit
import SavannaKit
import Lioness
import Cub
import InputAssistant
import PanelKit

class DocumentViewController: UIViewController {

	@IBOutlet weak var contentWrapperView: UIView!
	@IBOutlet weak var contentView: UIView!

	var document: SavannaDocument?
	
	var textDocument: TextDocument? {
		guard let document = self.document else {
			return nil
		}
		
		switch document {
		case .cub(let cubDoc):
			return cubDoc
			
		case .prideland(let pridelandDoc):
			return pridelandDoc
		}
		
	}
	

	@IBOutlet weak var consoleLogTextView: UITextView!
	@IBOutlet weak var sourceTextView: SyntaxTextView!

	@IBOutlet weak var stackView: UIStackView!
	
	let autoCompleteManager = CubSyntaxAutoCompleteManager()
	let inputAssistantView = InputAssistantView()
	
	func docItems() -> [DocumentationItem] {
		return DocumentationGenerator().items(runner: getRunner())
	}
	
	var autoCompleter: AutoCompleter!

	var cubManualPanelViewController: PanelViewController!

	
	private var textViewSelectedRangeObserver: NSKeyValueObservation?

	var manualBarButtonItem: UIBarButtonItem!

	override func viewDidLoad() {
		super.viewDidLoad()
		
		autoCompleter = AutoCompleter(documentation: docItems())
		
		let cubManualURL = Bundle.main.url(forResource: "book", withExtension: "html", subdirectory: "cub-guide.htmlcontainer")!
		let cubManualVC = UIStoryboard.main.manualWebViewController(htmlURL: cubManualURL)
		cubManualPanelViewController = PanelViewController(with: cubManualVC, in: self)
		cubManualVC.title = "The Cub Programming Language"
		
		let manualButton = UIButton(type: .system)
		manualButton.setTitle("?", for: .normal)
		manualButton.titleLabel?.font = UIFont.systemFont(ofSize: 28)
		
		manualButton.addTarget(self, action: #selector(showManual(_:)), for: .touchUpInside)
		
		manualBarButtonItem = UIBarButtonItem(customView: manualButton)
		
		self.navigationItem.rightBarButtonItems =  (self.navigationItem.rightBarButtonItems ?? []) + [manualBarButtonItem]
		
		sourceTextView.delegate = self
		sourceTextView.theme = Cub.DefaultTheme()
		
//		self.navigationController?.navigationBar.shadowImage = UIImage()
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_ :)), name: .UIKeyboardWillChangeFrame, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_ :)), name: .UIKeyboardWillHide, object: nil)

		sourceTextView.text = ""
		
		// Set up auto complete manager
		autoCompleteManager.delegate = inputAssistantView
		autoCompleteManager.dataSource = self
		
		// Set up input assistant and text view for auto completion
		inputAssistantView.delegate = self
		inputAssistantView.dataSource = autoCompleteManager
		inputAssistantView.attach(to: sourceTextView.contentTextView)
		
		inputAssistantView.leadingActions = [
			InputAssistantAction(image: DocumentViewController.tabImage, target: self, action: #selector(insertTab))
		]

		textDocument?.open(completionHandler: { [weak self] (success) in
			
			guard let `self` = self else {
				return
			}
			
			if success {
				
				self.sourceTextView.text = self.document?.text ?? ""
				
				// Calculate layout for full document, so scrolling is smooth.
//				self.sourceTextView.layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: self.textView.text.count))
				
			} else {
				
				self.showAlert("Error", message: "Document could not be opened.", dismissCallback: {
					self.dismiss(animated: true, completion: nil)
				})
				
			}
			
		})
		
	}
	
	private static var tabImage: UIImage {
		return UIGraphicsImageRenderer(size: .init(width: 24, height: 24)).image(actions: { context in
			
			let path = UIBezierPath()
			path.move(to: CGPoint(x: 1, y: 12))
			path.addLine(to: CGPoint(x: 20, y: 12))
			path.addLine(to: CGPoint(x: 15, y: 6))

			path.move(to: CGPoint(x: 20, y: 12))
			path.addLine(to: CGPoint(x: 15, y: 18))

			path.move(to: CGPoint(x: 23, y: 6))
			path.addLine(to: CGPoint(x: 23, y: 18))

			UIColor.white.setStroke()
			path.lineWidth = 2
			path.lineCapStyle = .butt
			path.lineJoinStyle = .round
			path.stroke()

			context.cgContext.addPath(path.cgPath)
			
		}).withRenderingMode(.alwaysOriginal)
	}
	
	
	@objc
	func showManual(_ sender: UIButton) {
		
		presentPopover(self.cubManualPanelViewController, from: manualBarButtonItem, backgroundColor: .white)
		
	}
	
	private func presentPopover(_ viewController: UIViewController, from sender: UIBarButtonItem, backgroundColor: UIColor) {
		
		// prevent a crash when the panel is floating.
		viewController.view.removeFromSuperview()
		
		viewController.modalPresentationStyle = .popover
		viewController.popoverPresentationController?.barButtonItem = sender
		viewController.popoverPresentationController?.backgroundColor = backgroundColor
		
		present(viewController, animated: true, completion: nil)
	}
	
	
	@objc func insertTab() {
		
		sourceTextView.insertText("\t")
		
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		sourceTextView.tintColor = self.view.tintColor
		
	}
	
	@objc func keyboardWillHide(_ notification: NSNotification) {

		guard let userInfo = notification.userInfo else {
			return
		}
		
		updateForKeyboard(with: userInfo, to: 0.0)

	}
	
	@objc func keyboardWillChangeFrame(_ notification: NSNotification) {
		guard let userInfo = notification.userInfo else {
			return
		}
		
		guard let endFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
			return
		}
		
		let convertedFrame = self.sourceTextView.convert(endFrame, from: nil).intersection(self.sourceTextView.bounds)
	
		let bottomInset = convertedFrame.size.height
		
		updateForKeyboard(with: userInfo, to: bottomInset)

	}
	
	func updateForKeyboard(with info: [AnyHashable: Any], to bottomInset: CGFloat) {

		let duration = (info[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.0
		let animationCurveRawNSN = info[UIKeyboardAnimationCurveUserInfoKey] as? NSNumber
		let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIViewAnimationOptions.curveEaseInOut.rawValue
		let animationCurve = UIViewAnimationOptions(rawValue: animationCurveRaw)
		
		UIView.animate(withDuration: duration, delay: 0.0, options: [animationCurve], animations: {
			
			self.sourceTextView.contentInset.bottom = bottomInset
			
		}, completion: nil)
		
	}
	
	@IBAction func toggleAxis(_ sender: UIBarButtonItem) {
	
		UIView.animate(withDuration: 0.3) {
			
			if self.stackView.axis == .horizontal {
				self.stackView.axis = .vertical
			} else {
				self.stackView.axis = .horizontal
			}
			
		}
		
	}
	
	@IBAction func clearConsole(_ sender: UIBarButtonItem) {
		
		self.consoleLogTextView.text = ""

	}
	
	func getRunner() -> Cub.Runner {
		
		let runner = Cub.Runner(logDebug: false, logTime: false)

		let captureShellCommand = """
						The captureShell function can only be used in OpenTerm.
						This function is included in Savanna for testing OpenTerm script, without actually executing any commands.
						- Returns: an empty string
						"""
		
		runner.registerExternalFunction(documentation: captureShellCommand, name: "captureShell", argumentNames: ["command"], returns: true) { (args, completionHandler) in
			
			DispatchQueue.main.async {
				self.consoleLogTextView.text = self.consoleLogTextView.text + "The captureShell function can only be used in OpenTerm."
			}
			
			_ = completionHandler(.number(0))
			
		}
		
		
		let shellCommand = """
						The shell function can only be used in OpenTerm.
						This function is included in Savanna for testing OpenTerm script, without actually executing any commands.
						- Returns: 0
						"""
		runner.registerExternalFunction(documentation: shellCommand, name: "shell", argumentNames: ["command"], returns: true) { (args, completionHandler) in
			
			DispatchQueue.main.async {
				self.consoleLogTextView.text = self.consoleLogTextView.text + "The shell function can only be used in OpenTerm."
			}
			
			_ = completionHandler(.number(0))
			
		}
		
		let printDoc = """
						Display something on screen.
						- Parameter input: the value you want to print.
						"""
		
		runner.registerExternalFunction(documentation: printDoc, name: "print", argumentNames: ["input"], returns: true) { (args, completionHandler) in
			
			guard let input = args["input"] else {
				_ = completionHandler(.string(""))
				return
			}
			
			let parameter = input.description(with: runner.compiler)
			
			DispatchQueue.main.async {
				self.consoleLogTextView.text = self.consoleLogTextView.text + "\(parameter)"
			}
			
			_ = completionHandler(.string(""))
		}
		
		let printlnDoc = """
						Display something on screen with a new line added at the end.
						- Parameter input: the value you want to print.
						"""
		runner.registerExternalFunction(documentation: printlnDoc, name: "println", argumentNames: ["input"], returns: true) { (args, completionHandler) in
			
			guard let input = args["input"] else {
				_ = completionHandler(.string(""))
				return
			}
			
			let parameter = input.description(with: runner.compiler)
			
			DispatchQueue.main.async {
				self.consoleLogTextView.text = self.consoleLogTextView.text + "\n\(parameter)"
			}
			
			_ = completionHandler(.string(""))
		}
		
		return runner
	}
	
	@IBAction func runSource(_ sender: UIBarButtonItem) {
		
		consoleLogTextView.text = ""
		
		let runner = getRunner()
		runner.delegate = self
		
		let source = self.sourceTextView.text
		
		DispatchQueue.global(qos: .background).async {
			
			do {
				try runner.run(source)
				
				DispatchQueue.main.async {
//					self.progressToolbarItem.text = "Finished running"
				}
				
			} catch {
				print(error)
				DispatchQueue.main.async {
					
					let errorString: String
					
					if let displayableError = error as? Cub.DisplayableError {
						
						errorString = displayableError.description(inSource: source)
						
					} else {
						
						errorString = "Unknown error occurred"

					}
					
					self.consoleLogTextView.text = self.consoleLogTextView.text + "\(errorString)\n"
				}
				
			}
			
		}
		
	}
	
	
	@IBAction func dismissDocumentViewController() {
		
		let currentText = self.document?.text ?? ""
		
		self.textDocument?.text = self.sourceTextView.text
		
		if currentText != self.sourceTextView.text {
			self.textDocument?.updateChangeCount(.done)
		}
		
		dismiss(animated: true) {
			self.textDocument?.close(completionHandler: nil)
		}
	}
	
}

extension DocumentViewController: Cub.RunnerDelegate {
	
	@nonobjc func log(_ message: String) {
		// TODO: refactor to function, scroll to bottom
		consoleLogTextView.text! += "\n\(message)"

		print(message)
	}
	
	@nonobjc func log(_ error: Error) {
		
		consoleLogTextView.text! += "\n\(error)"

		print(error)
	}
	
	@nonobjc func log(_ token: Cub.Token) {
		
		consoleLogTextView.text! += "\n\(token)"

		print(token)
	}
	
}

extension DocumentViewController: SyntaxTextViewDelegate {

	func didChangeSelectedRange(_ syntaxTextView: SyntaxTextView, selectedRange: NSRange) {
		autoCompleteManager.reloadData()
	}
	
	func didChangeText(_ syntaxTextView: SyntaxTextView) {
		autoCompleteManager.reloadData()
	}
	
	func lexerForSource(_ source: String) -> SavannaKit.Lexer {
		return Cub.Lexer(input: source)
	}
	
}

extension DocumentViewController: CubSyntaxAutoCompleteManagerDataSource {
	
	func completions() -> [CubSyntaxAutoCompleteManager.Completion] {
		
		guard let text = sourceTextView.contentTextView.text else {
			return []
		}
		
		let selectedRange = sourceTextView.contentTextView.selectedRange
		
		guard let swiftRange = Range(selectedRange, in: text) else {
			return []
		}
		
		let cursor = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
		
		let suggestions = autoCompleter.completionSuggestions(for: sourceTextView.contentTextView.text, cursor: cursor)
		
		return suggestions.map({ CubSyntaxAutoCompleteManager.Completion($0.content, data: $0) })
	}
	
}

extension DocumentViewController: InputAssistantViewDelegate {
	
	func inputAssistantView(_ inputAssistantView: InputAssistantView, didSelectSuggestionAtIndex index: Int) {
		let completion = autoCompleteManager.completions[index]
		
		let suggestion = completion.data
		
		sourceTextView.insertText(suggestion.content)
		
		let newSource = sourceTextView.text
		
		let insertStart = newSource.index(newSource.startIndex, offsetBy: suggestion.insertionIndex)
		let cursorAfterInsertion = newSource.index(insertStart, offsetBy: suggestion.cursorAfterInsertion)
		
		if let utf16Index = cursorAfterInsertion.samePosition(in: newSource) {
			let distance = newSource.utf16.distance(from: newSource.utf16.startIndex, to: utf16Index)
			
			sourceTextView.contentTextView.selectedRange = NSRange(location: distance, length: 0)
		}
		
	}
	
}

extension DocumentViewController: PanelManager {
	
	var panels: [PanelViewController] {
		return [cubManualPanelViewController]
	}
	
	var panelContentWrapperView: UIView {
		return self.contentWrapperView
	}
	
	var panelContentView: UIView {
		return self.contentView
	}
	
	func maximumNumberOfPanelsPinned(at side: PanelPinSide) -> Int {
		return 2
	}
	
}
