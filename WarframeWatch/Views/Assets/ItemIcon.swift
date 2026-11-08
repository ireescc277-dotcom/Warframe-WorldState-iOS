import SwiftUI
import UIKit

/// 物品缩略图：先找打进 App 的 Asset Catalog，找不到再回 CDN 拿。
///
/// 图片是 warframe.market 的 128×128 缩略图（DE 的游戏资产，非商业粉丝项目可用）。
/// 打包的那一份覆盖当前背包里所有套装和遗物；如果以后数据改由 VPS 下发、
/// 出现 App 里没有的新条目，`remote` 还能兜住。
public struct ItemIcon: View {
    private let local: String?
    private let remote: String?
    private let size: CGFloat

    private static let cdn = "https://warframe.market/static/assets/"

    public init(_ local: String?, remote: String? = nil, size: CGFloat = 40) {
        self.local = local
        self.remote = remote
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let url = remoteURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    case .failure:
                        placeholder
                    default:
                        placeholder.opacity(0.6)
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var localImage: UIImage? {
        guard let local = local, !local.isEmpty else { return nil }
        return UIImage(named: local)
    }

    private var remoteURL: URL? {
        guard let remote = remote, !remote.isEmpty else { return nil }
        return URL(string: ItemIcon.cdn + remote)
    }

    /// 没有图的时候不能留个洞，否则一行里文字会跳位。
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(WFUI.surface)
            .overlay(
                Image(systemName: "shippingbox")
                    .font(.system(size: size * 0.34))
                    .foregroundColor(WFTheme.textMuted.opacity(0.5))
            )
    }
}
