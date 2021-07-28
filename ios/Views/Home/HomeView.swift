//
//  HomeView.swift
//  ios
//
//  Created by Mason Phillips on 3/25/21.
//

import UIKit
import Neon
import RxCocoa
import RxDataSources
import RxFlow
import RxSwift
import SCLAlertView
import Network
import SwiftyUserDefaults
import Kingfisher

class HomeView: BaseController {
    var rightButton: UIBarButtonItem {
        let b = UIBarButtonItem(title: "cogs", style: .plain, target: self, action: #selector(settings))
        b.setTitleTextAttributes([.font: UIFont(name: "FontAwesome5Pro-Solid", size: 20)!], for: .normal)
        b.setTitleTextAttributes([.font: UIFont(name: "FontAwesome5Pro-Solid", size: 20)!], for: .highlighted)
        return b
    }
    
    var leftButton: UIBarButtonItem {
        let b = UIBarButtonItem(title: "filter", style: .plain, target: self, action: #selector(orgFilter))
        b.setTitleTextAttributes([.font: UIFont(name: "FontAwesome5Pro-Solid", size: 20)!], for: .normal)
        b.setTitleTextAttributes([.font: UIFont(name: "FontAwesome5Pro-Solid", size: 20)!], for: .highlighted)
        return b
    }

    let refresh = UIRefreshControl()
    let table = UITableView(frame: .zero, style: .insetGrouped)
    
    var observers: Array<DefaultsDisposable> = []
    let model: HomeModelType
    let services: AppServices
    
    override init(_ stepper: Stepper, _ services: AppServices) {
        model = HomeModel(services)
        self.services = services
        super.init(stepper, services)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        for observer in observers {
            observer.dispose()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self,
                                                selector: #selector(checkPasteboard),
                                                name: UIApplication.willEnterForegroundNotification,
                                                object: nil)
        
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = rightButton
        navigationItem.leftBarButtonItem = leftButton
        navigationItem.title = "\(services.settings.orgFilter.short)Dex"
        
        let dataSource = RxTableViewSectionedReloadDataSource<StreamerItemModel> { _, table, index, item -> UITableViewCell in
            let cell = table.dequeueReusableCell(withIdentifier: StreamerCell.identifier, for: index)
            (cell as? StreamerCell)?.configure(with: item, services: self.services)
            return cell
        }
        dataSource.titleForHeaderInSection = { source, index -> String in
            source.sectionModels[index].title
        }
        
        let orgObserver = Defaults.observe(\.orgFilter) { _ in self.reload() }
        let thumbnailsObserver = Defaults.observe(\.thumbnails) { _ in self.reload() }
        let blurObserver = Defaults.observe(\.thumbnailBlur) { _ in self.reload() }
        let darkenObserver = Defaults.observe(\.thumbnailDarken) { _ in self.reload() }
        observers.append(contentsOf: [orgObserver, thumbnailsObserver, blurObserver, darkenObserver])
        
        refresh.rx.controlEvent(.valueChanged).bind(to: model.input.refresh).disposed(by: bag)
        model.output.refreshDoneDriver.drive(refresh.rx.isRefreshing).disposed(by: bag)
        
        table.rx.setDelegate(self).disposed(by: bag)
        table.register(StreamerCell.self, forCellReuseIdentifier: StreamerCell.identifier)
        model.output.streamersDriver
            .map { $0.sections() }
            .drive(table.rx.items(dataSource: dataSource))
            .disposed(by: bag)
        view.addSubview(table)
        
        model.input.loadStreamers(services.settings.orgFilter)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        checkPasteboard()
    }
    
    @objc func checkPasteboard() {
        guard (model as? HomeModel)?.services.settings.clipboard ?? false else { return }
        
        let pasteboard = UIPasteboard.general.urls ?? []
            
        for url in pasteboard {
            if let url = URLComponents(url: url, resolvingAgainstBaseURL: false), (url.host == "www.youtube.com" || url.host == "youtu.be" || url.host == "m.youtube.com") {
                let alert = SCLAlertView()
                
                alert.addButton("Let's Go!") {
                    let final: String
                    
                    if let id = url.queryItems?.filter({ $0.name == "v" }).first?.value {
                        final = id
                    } else {
                        final = url.path.replacingOccurrences(of: "/", with: "")
                    }
                    
                    self.stepper.steps.accept(AppStep.view(final))
                }
                
                alert.showInfo("Youtube Link Detected!",
                               subTitle: "We detected a Youtube link in your clipboard. Would you like to access this stream?")
            }
        }
    }
    
    @objc func settings() {
        stepper.steps.accept(AppStep.settings)
    }
    
    @objc func orgFilter() {
        stepper.steps.accept(AppStep.filter)
    }
    
    private func reload() {
        model.input.refresh.accept(())
        DispatchQueue.main.async {
            self.navigationItem.title = "\(self.services.settings.orgFilter.short)Dex"
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        table.fillSuperview(left: 5, right: 5, top: 15, bottom: 5)
    }
}

extension HomeView: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let vid = model.output.video(for: indexPath.section, and: indexPath.row)
        stepper.steps.accept(AppStep.view(vid))
    }


    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let index = indexPath.row
        let identifier = "\(index)" as NSString
    
        func makeThumbnailPreview() -> UIViewController {
            let viewController = UIViewController()
            let popoutView: UIView = UIView()
            let imageView: UIImageView = UIImageView()
            popoutView.frame = CGRect(x: 0, y: 0, width: 333, height: 999)
            popoutView.clipsToBounds = true
            
            imageView.kf.indicatorType = .activity
            imageView.kf.setImage(with: model.output.thumbnail(for: indexPath.section, and: indexPath.row))
            popoutView.addSubview(imageView)
            imageView.anchorToEdge(.top, padding: 0, width: 333, height: 187)
            
            let titleText = model.output.title(for: indexPath.section, and: indexPath.row)
            let nsText = titleText as NSString?
            let textSize = nsText?.boundingRect(with: popoutView.frame.size, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18)], context: nil).size
            
            let title = UILabel()
            title.lineBreakMode = .byWordWrapping
            title.numberOfLines = 0
            title.text = titleText
            title.font = .systemFont(ofSize: 18)
            popoutView.addSubview(title)
            //title.backgroundColor = .blue
            
            title.sizeToFit()
            title.align(.underCentered, relativeTo: imageView, padding: 10, width: 300, height: textSize?.height ?? 0)
            
            
            print(title.height + imageView.height + 20)
            let popoutHeight = title.height + imageView.height + 20
            popoutView.frame = CGRect(x: 0, y: 0, width: 333, height: popoutHeight)
            viewController.view = popoutView
            viewController.preferredContentSize = popoutView.frame.size
        
            return viewController
        }
    
        return UIContextMenuConfiguration(identifier: identifier, previewProvider: makeThumbnailPreview) { _ in
            _ = UIAction(title: "Favorite", image: UIImage(systemName: "heart.fill")) { _ in
                print("Favorite")
            }
        
            _ = UIAction(title: "Description", image: UIImage(systemName: "newspaper.fill")) { _ in
                print("Description")
                print(self.model.output.description(for: indexPath.section, and: indexPath.row))
            }
        
            let youtubeAction = UIAction(title: "Open in Youtube", image: UIImage(systemName: "play.rectangle.fill")) { _ in
                let youtubeId = self.model.output.video(for: indexPath.section, and: indexPath.row)
                var youtubeUrl = URL(string:"youtube://\(youtubeId)")!
                if UIApplication.shared.canOpenURL(youtubeUrl){
                    UIApplication.shared.open(youtubeUrl)
                } else {
                    youtubeUrl = URL(string:"https://www.youtube.com/watch?v=\(youtubeId)")!
                    UIApplication.shared.open(youtubeUrl)
                }
            }
        
            return UIMenu(title: "", image: nil, children: [youtubeAction])
        }
    }
}
