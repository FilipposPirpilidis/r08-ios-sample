import UIKit
import Combine
import Core

final class HomeViewController: UIViewController {
    private let viewModel: HomeViewModel
    private var cancellables = Set<AnyCancellable>()

    private let viewDidLoadSubject = PassthroughSubject<Void, Never>()
    private let connectTapSubject = PassthroughSubject<Void, Never>()
    private let disconnectTapSubject = PassthroughSubject<Void, Never>()
    private let touchOnTapSubject = PassthroughSubject<Void, Never>()
    private let touchOffTapSubject = PassthroughSubject<Void, Never>()
    private let unlinkTapSubject = PassthroughSubject<Void, Never>()
    private let deviceSelectedSubject = PassthroughSubject<SmartRingDiscoveredDevice, Never>()

    private var discoveredDevices: [SmartRingDiscoveredDevice] = []

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alwaysBounceVertical = true
        return view
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.text = "State: -"
        return label
    }()

    private let linkedTargetLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.text = "No linked target"
        return label
    }()

    private let tapEventLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .systemBlue
        label.numberOfLines = 2
        label.text = "Waiting for tap events..."
        return label
    }()

    private let connectButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Scan / Connect", for: .normal)
        return button
    }()

    private let disconnectButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Disconnect", for: .normal)
        return button
    }()

    private let unlinkButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Unlink", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        return button
    }()

    private let touchOnButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Touch Control ON", for: .normal)
        button.isEnabled = false
        return button
    }()

    private let touchOffButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Touch Control OFF", for: .normal)
        button.isEnabled = false
        return button
    }()

    private let devicesTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.text = "Smart Rings (Tap To Link Target)"
        return label
    }()

    private let devicesTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.layer.cornerRadius = 10
        return table
    }()

    private let logsTextView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isEditable = false
        view.isScrollEnabled = true
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.backgroundColor = UIColor.secondarySystemBackground
        view.layer.cornerRadius = 10
        return view
    }()

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        buildLayout()
        bindViewModel()

        devicesTableView.dataSource = self
        devicesTableView.delegate = self

        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        disconnectButton.addTarget(self, action: #selector(disconnectTapped), for: .touchUpInside)
        touchOnButton.addTarget(self, action: #selector(touchOnTapped), for: .touchUpInside)
        touchOffButton.addTarget(self, action: #selector(touchOffTapped), for: .touchUpInside)
        unlinkButton.addTarget(self, action: #selector(unlinkTapped), for: .touchUpInside)

        viewDidLoadSubject.send(())
    }

    private func bindViewModel() {
        let input = HomeViewModel.Input(
            viewDidLoadIn: viewDidLoadSubject.eraseToAnyPublisher(),
            connectTapIn: connectTapSubject.eraseToAnyPublisher(),
            disconnectTapIn: disconnectTapSubject.eraseToAnyPublisher(),
            touchOnTapIn: touchOnTapSubject.eraseToAnyPublisher(),
            touchOffTapIn: touchOffTapSubject.eraseToAnyPublisher(),
            unlinkTapIn: unlinkTapSubject.eraseToAnyPublisher(),
            deviceSelectedIn: deviceSelectedSubject.eraseToAnyPublisher()
        )

        let output = viewModel.convert(input: input)

        output.connectionStateOut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.stateLabel.text = "State: \(Self.stringValue(for: state))"
                let isConnected: Bool
                if case .connected = state {
                    isConnected = true
                } else {
                    isConnected = false
                }
                self?.touchOnButton.isEnabled = isConnected
                self?.touchOffButton.isEnabled = isConnected
                self?.devicesTitleLabel.isHidden = isConnected
                self?.devicesTableView.isHidden = isConnected
            }
            .store(in: &cancellables)

        output.linkedTargetOut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.linkedTargetLabel.text = value
            }
            .store(in: &cancellables)

        output.tapEventTextOut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.tapEventLabel.text = value
            }
            .store(in: &cancellables)

        output.discoveredDevicesOut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.discoveredDevices = devices
                self?.devicesTableView.reloadData()
            }
            .store(in: &cancellables)

        output.logsOut
            .receive(on: DispatchQueue.main)
            .scan([String]()) { current, next in
                Array((current + [next]).suffix(400))
            }
            .sink { [weak self] lines in
                let text = lines.joined(separator: "\n")
                self?.logsTextView.text = text + "\n\n"
                guard !text.isEmpty else { return }
                let range = NSRange(location: max(text.count - 1, 0), length: 1)
                self?.logsTextView.scrollRangeToVisible(range)
            }
            .store(in: &cancellables)

        output.connectTapOut.sink { _ in }.store(in: &cancellables)
        output.disconnectTapOut.sink { _ in }.store(in: &cancellables)
        output.touchOnTapOut.sink { _ in }.store(in: &cancellables)
        output.touchOffTapOut.sink { _ in }.store(in: &cancellables)
        output.unlinkTapOut.sink { _ in }.store(in: &cancellables)
        output.deviceSelectedOut.sink { _ in }.store(in: &cancellables)
    }

    @objc private func connectTapped() {
        connectTapSubject.send(())
    }

    @objc private func disconnectTapped() {
        disconnectTapSubject.send(())
    }

    @objc private func touchOnTapped() {
        touchOnTapSubject.send(())
    }

    @objc private func touchOffTapped() {
        touchOffTapSubject.send(())
    }

    @objc private func unlinkTapped() {
        unlinkTapSubject.send(())
    }

    private func buildLayout() {
        let buttonStack = UIStackView(arrangedSubviews: [connectButton, disconnectButton, unlinkButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 8
        buttonStack.distribution = .fillEqually

        let touchStack = UIStackView(arrangedSubviews: [touchOnButton, touchOffButton])
        touchStack.translatesAutoresizingMaskIntoConstraints = false
        touchStack.axis = .horizontal
        touchStack.spacing = 8
        touchStack.distribution = .fillEqually

        let logsTitle = titleLabel("BLE Logs")

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)

        contentStack.addArrangedSubview(stateLabel)
        contentStack.addArrangedSubview(linkedTargetLabel)
        contentStack.addArrangedSubview(tapEventLabel)
        contentStack.addArrangedSubview(buttonStack)
        contentStack.addArrangedSubview(touchStack)
        contentStack.addArrangedSubview(devicesTitleLabel)
        contentStack.addArrangedSubview(devicesTableView)
        contentStack.addArrangedSubview(logsTitle)
        contentStack.addArrangedSubview(logsTextView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            devicesTableView.heightAnchor.constraint(equalToConstant: 240),
            logsTextView.heightAnchor.constraint(equalToConstant: 560)
        ])
    }

    private func titleLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.text = title
        return label
    }

    private static func stringValue(for state: SmartRingConnectionState) -> String {
        switch state {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case let .error(message): return "Error: \(message)"
        }
    }
}

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        discoveredDevices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "device")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "device")

        let device = discoveredDevices[indexPath.row]
        cell.textLabel?.text = device.name
        cell.detailTextLabel?.text = "RSSI: \(device.rssi) | \(device.id.uuidString)"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let device = discoveredDevices[indexPath.row]
        deviceSelectedSubject.send(device)
    }
}
