//
//  StreamView.swift
//  ios
//
//  Created by Mason Phillips on 3/25/21.
//

import UIKit
import AVKit
import RxCocoa
import RxFlow
import RxSwift
import Neon
import SCLAlertView
import M3U8Kit

class StreamView: BaseController {
    var videoPlayer = AVPlayerViewController()
    let videoView   = UIView(frame: .zero)
    var player: AVPlayer? = AVPlayer(playerItem: nil)
    
    let chatTable = ChatTable(frame: .zero, style: .plain)
    let chatControl: UISegmentedControl
    var caption: UILabel = UILabel()
    let captionFontSize: CGFloat = 17.0
    
    let model: StreamModelType
    let settingsService: SettingsService
    let sharedAudio = AVAudioSession.sharedInstance()
    
    var leftButton: UIBarButtonItem {
        let b = UIBarButtonItem(title: "times", style: .plain, target: self, action: #selector(closeStream))
        b.setTitleTextAttributes([.font: UIFont(name: "FontAwesome5Pro-Solid", size: 20)!], for: .normal)
        b.setTitleTextAttributes([.font: UIFont(name: "FontAwesome5Pro-Solid", size: 20)!], for: .highlighted)
        return b
    }
    var rightButton: UIBarButtonItem {
        let b = UIBarButtonItem(title: "cogs", style: .plain, target: self, action: #selector(settings))
        b.setTitleTextAttributes([.font: UIFont(name: "FontAwesome5Pro-Solid", size: 20)!], for: .normal)
        b.setTitleTextAttributes([.font: UIFont(name: "FontAwesome5Pro-Solid", size: 20)!], for: .highlighted)
        return b
    }
    
    override init(_ stepper: Stepper, _ services: AppServices) {
        model = StreamModel(services)
        settingsService = services.settings
        
        let actions = [
            UIAction(title: "All Chat") { _ in return },
            UIAction(title: "LiveTL Mode") { _ in return }
        ]
        chatControl = UISegmentedControl(frame: .zero, actions: actions)
        chatControl.selectedSegmentIndex = 0
        
        super.init(stepper, services)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        model.output.errorRelay.compactMap { $0 }.subscribe(onNext: handle(_:)).disposed(by: bag)
        errorRelay.compactMap { $0 }.subscribe(onNext: handle(_:)).disposed(by: bag)
        
        navigationItem.leftBarButtonItem = leftButton
        navigationItem.rightBarButtonItem = rightButton
        
        view.backgroundColor = .systemBackground
        
        model.output.videoDriver.compactMap { $0 }
            .drive(onNext: { item in
                DispatchQueue.main.async { [self] in
                    let m3u8 = try! M3U8PlaylistModel(url: item.streamURL!)
                    var streamURL: URL? = item.streamURL!
                    
                    for i in 0..<m3u8.masterPlaylist.xStreamList.count {
                        if m3u8.masterPlaylist.xStreamList.xStreamInf(at: i)?.resolution == YouTubeResolution.auto.mediaResolution {
                            streamURL = m3u8.masterPlaylist.xStreamList.xStreamInf(at: i).m3u8URL()
                        }
                    }
                    let playerItem = AVPlayerItem(url: streamURL!)
                    
                    player?.replaceCurrentItem(with: playerItem)
                    videoPlayer.player = player
                    player?.play()
                    
                    let time = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                    videoPlayer.player?.addPeriodicTimeObserver(forInterval: time, queue: .main) { time in
                        model.input.timeControl.accept((time.seconds, item.identifier))
                    }
                }
            }).disposed(by: bag)
        videoView.addSubview(videoPlayer.view)
        addChild(videoPlayer)
        view.addSubview(videoView)
        videoPlayer.didMove(toParent: self)
        
        
        caption.textColor = .white
        caption.font = .systemFont(ofSize: captionFontSize)
        caption.textAlignment = .center
        caption.backgroundColor = .black.withAlphaComponent(0.8)
        caption.numberOfLines = 0
        caption.lineBreakMode = .byWordWrapping
        caption.text = ""
        
        if !settingsService.captions {
            caption.isHidden = true
        }
        
        model.output.captionDriver.drive(onNext: { [self] item in
            if item.last != nil {
                //remove emotes
                var fullMessage = String()
                
                for m in item.last!.displayMessage {
                    switch m {
                    case .text(let s):
                        fullMessage.append(s)
                    case .emote:
                        continue
                    }
                }
                
                //calculate view size
                let nsText = fullMessage as NSString
                
                let textSize = nsText.boundingRect(with: videoPlayer.view.frame.size, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: captionFontSize)], context: nil).size
                caption.frame.size = textSize
                
                caption.align(.underCentered, relativeTo: videoPlayer.view, padding: ((videoPlayer.view.height/8)*(-1)) - caption.height, width: caption.width, height: caption.height)
                
                //update text
                caption.text = fullMessage
            }
        }).disposed(by: bag)
        videoPlayer.contentOverlayView?.addSubview(caption)
        
        chatControl.rx.value.compactMap { ChatControlType(rawValue: $0) }
            .bind(to: model.input.chatControl)
            .disposed(by: bag)
        view.addSubview(chatControl)
        
        model.output.chatDriver.drive(chatTable.rx.items(cellIdentifier: ChatCell.identifier, cellType: ChatCell.self)) { index, item, cell in
            let ts = (self.model as? StreamModel)?.services.settings.timestamps ?? true
            cell.configure(item, useTimestamps: ts)
        }.disposed(by: bag)
        model.output.loadingDriver.drive(chatTable.loadingRelay).disposed(by: bag)
        model.output.emptyDriver.drive(chatTable.emptyRelay).disposed(by: bag)
        chatTable.rx.setDelegate(model as! StreamModel).disposed(by: bag)
        view.addSubview(chatTable)
        
        do {
            try sharedAudio.setCategory(.playback, mode: .moviePlayback)
            try sharedAudio.setActive(true)
        } catch {
            print("AVAudioSession error: \(error.localizedDescription)")
            errorRelay.accept(NSError(domain: "app.livetl.ios", code: 100, userInfo: [
                NSLocalizedDescriptionKey: Bundle.main.localizedString(forKey: "Audio will only play if device in not in silent mode.", value: "Audio will only play if device in not in silent mode.", table: "Localizeable")
            ]))
        }
    }
    
    func load(_ id: String) {
        model.input.load(id)
    }
    
    @objc func closeStream() {
        videoPlayer.player?.pause()
        videoPlayer.player = nil
        player = nil
        stepper.steps.accept(AppStep.home)
    }
    
    @objc func settings() {
        stepper.steps.accept(AppStep.settings)
    }
    
    override func handle(_ error: Error) {
        let nserror = error as NSError
        
        if nserror.code == -6, let responseString = nserror.userInfo["consentHtmlData"] as? String {
            self.closeStream()
            return stepper.steps.accept(AppStep.toConsent(responseString))
//        } else if nserror.code == -2 && nserror.localizedDescription == "Join this channel to get access to members-only content like this video, and other exclusive perks." {
//            let alert = SCLAlertView()
//            alert.addButton("Go Back") {
//                self.closeStream()
//            }
//            alert.addButton("Sign In to Youtube") {
//                // TODO: implement Sign in to Youtube
//                self.closeStream()
//            }
//            alert.showInfo("Member Only Stream", subTitle: "It looks like you're trying to watch a member only stream. If you're already a member of this channel, you can sign into Youtube to watch it!")
        } else {
            let alert = SCLAlertView()
            alert.addButton(Bundle.main.localizedString(forKey: "Go Back", value: "Go Back", table: "Localizeable")) {
                self.closeStream()
            }
            alert.showError(Bundle.main.localizedString(forKey: "An Error Occurred", value: "An Error Occurred", table: "Localizeable"), subTitle: error.localizedDescription)
        }
        
        //super.handle(error)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        view.bringSubviewToFront(videoView)
                
        switch UIDevice.current.model {
        case "iPhone": view.width < view.height ? iPhoneLayoutPortrait() : iPhoneLayoutLandscape()
        case "iPad"  : view.width < view.height ? iPadLayoutPortrait() : iPadLayoutLandscape()
            
        default: break
        }
        
        videoPlayer.view.frame = videoView.bounds
        navigationController?.setNavigationBarHidden(view.width > view.height, animated: false)
        videoPlayer.contentOverlayView?.frame = videoView.bounds
        
        let nsText = caption.text! as NSString
        let textSize = nsText.boundingRect(with: videoPlayer.view.frame.size, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: captionFontSize)], context: nil).size
        caption.frame.size = textSize
        caption.align(.underCentered, relativeTo: videoPlayer.view, padding: ((videoPlayer.view.height/8)*(-1)) - caption.height, width: caption.width, height: caption.height)
        
    }
    
    func iPhoneLayoutPortrait() {
        let topHeight = (UIApplication.shared.delegate as? AppDelegate)?.topBarHeight ?? 0
        videoView.anchorAndFillEdge(.top, xPad: 0, yPad: topHeight, otherSize: 210)
        
        let chatTableHeight = view.height - (videoView.frame.maxY + 75)
        chatTable.anchorAndFillEdge(.bottom, xPad: 0, yPad: 20, otherSize: chatTableHeight)
        
        chatControl.align(.aboveCentered, relativeTo: chatTable, padding: 5, width: view.width - 10, height: 35)
    }
    func iPhoneLayoutLandscape() {
        videoView.anchorAndFillEdge(.left, xPad: 0, yPad: 0, otherSize: view.width * 0.65)
        
        chatTable.anchorInCorner(.bottomRight, xPad: 0, yPad: 0, width: view.width * 0.35, height: view.height - 45)
        
        let contentMarginRight = (UIApplication.shared.delegate as? AppDelegate)?.notchSize ?? 0
        chatControl.align(.aboveCentered, relativeTo: chatTable, padding: 5, width: view.width * 0.32 - contentMarginRight, height: 35)
    }
    
    func iPadLayoutPortrait() {
        videoView.anchorAndFillEdge(.top, xPad: 0, yPad: 0, otherSize: view.height * 0.6)
        chatTable.anchorAndFillEdge(.bottom, xPad: 0, yPad: 0, otherSize: view.height * 0.35)
        chatControl.align(.aboveCentered, relativeTo: chatTable, padding: 5, width: view.width - 10, height: 35)
    }
    func iPadLayoutLandscape() {
        videoView.anchorAndFillEdge(.left, xPad: 0, yPad: 0, otherSize: view.width * 0.7)
        chatTable.anchorInCorner(.bottomRight, xPad: 0, yPad: 0, width: view.width * 0.3, height: view.height - 85)
        chatControl.align(.aboveCentered, relativeTo: chatTable, padding: 2, width: view.width * 0.3, height: 35)
    }
}

