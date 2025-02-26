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
    
    var observers: [DefaultsDisposable] = []
    let model: HomeModelType
    let services: AppServices
    
    override init(_ stepper: RxFlow.Stepper, _ services: AppServices) {
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
            if let url = URLComponents(url: url, resolvingAgainstBaseURL: false), url.host == "www.youtube.com" || url.host == "youtu.be" || url.host == "m.youtube.com" {
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
                
                alert.showInfo(Bundle.main.localizedString(forKey: "Youtube Link Detected!", value: "Youtube Link Detected!", table: "Localizeable"),
                               subTitle: Bundle.main.localizedString(forKey: "We detected a Youtube link in your clipboard. Would you like to access this stream?", value: "We detected a Youtube link in your clipboard. Would you like to access this stream?", table: "Localizeable"))
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
//            let titleText = model.output.title(for: indexPath.section, and: indexPath.row)
//            let thumbnail = model.output.thumbnail(for: indexPath.section, and: indexPath.row)
//
//            let popoutView = UIHostingController(rootView:
//                VStack(alignment: .leading) {
//                    KFImage(thumbnail)
//                        .resizable()
//                        .aspectRatio(contentMode: .fit)
//                    Text(titleText!)
//                        .multilineTextAlignment(.leading)
//                        .minimumScaleFactor(0.01)
//                        .font(.system(size: 18))
//                }.background(GeometryReader { geom in
//                    Color.clear.onAppear {
//                        print(geom.size)
//                    }
//                }))
//
//            return popoutView
            
             let viewController = UIViewController()
             let popoutView: UIView = UIView()
             let imageView: UIImageView = UIImageView()
             popoutView.frame = CGRect(x: 0, y: 0, width: 333, height: 999)
             //popoutView.clipsToBounds = true

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

             title.sizeToFit()
             title.align(.underCentered, relativeTo: imageView, padding: 10, width: 300, height: textSize?.height ?? 0)
             title.leadingAnchor.constraint(equalTo: popoutView.safeAreaLayoutGuide.leadingAnchor, constant: 100).isActive = true
             title.trailingAnchor.constraint(equalTo: popoutView.safeAreaLayoutGuide.trailingAnchor, constant: -100).isActive = true
             title.layoutIfNeeded()

             let popoutHeight = title.height + imageView.height + 20
             popoutView.frame = CGRect(x: 0, y: 0, width: 333, height: popoutHeight)
             viewController.view = popoutView
             viewController.preferredContentSize = popoutView.frame.size

             return viewController
             
        }
    
        return UIContextMenuConfiguration(identifier: identifier, previewProvider: makeThumbnailPreview) { _ in
        
            _ = UIAction(title: "Description", image: UIImage(systemName: "newspaper.fill")) { _ in
                print(Bundle.main.localizedString(forKey: "Description", value: "Description", table: "Localizeable"))
                print(self.model.output.description(for: indexPath.section, and: indexPath.row))
            }
            
            let shareAction = UIAction(title: Bundle.main.localizedString(forKey: "Share", value: "Share", table: "Localizeable"), image: UIImage(systemName: "square.and.arrow.up")) { _ in
                let youtubeId = self.model.output.video(for: indexPath.section, and: indexPath.row)
                let items = [URL(string: "https://www.youtube.com/watch?v=\(youtubeId)")!]
                let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
                self.present(ac, animated: true)
            }
        
            let youtubeAction = UIAction(title: Bundle.main.localizedString(forKey: "Open in Youtube", value: "Open in Youtube", table: "Localizeable"), image: UIImage(systemName: "play.rectangle.fill")) { _ in
                let youtubeId = self.model.output.video(for: indexPath.section, and: indexPath.row)
                var youtubeUrl = URL(string: "youtube://\(youtubeId)")!
                if UIApplication.shared.canOpenURL(youtubeUrl) {
                    UIApplication.shared.open(youtubeUrl)
                } else {
                    youtubeUrl = URL(string: "https://www.youtube.com/watch?v=\(youtubeId)")!
                    UIApplication.shared.open(youtubeUrl)
                }
            }
            return UIMenu(title: "", image: nil, children: [shareAction, youtubeAction])
        }
    }
}
