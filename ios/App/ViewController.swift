import UIKit
import Capacitor

class ViewController: CAPBridgeViewController {

    override func capacitorDidLoad() {
        super.capacitorDidLoad()

        bridge?.registerPluginInstance(WorkspaceFilePlugin())

        print("[WorkspaceFile] Native plugin registered")
    }
}
