class SyncManager:

    def __init__(self, network):

        self.network = network

    def prepare_document(self):

        if not self.network.connect():

            print("Offline mode.")

            return True

        server = self.network.get_version()

        local = self.network.local_version()

        if server == local:

            print("Cache is current.")

            return True

        print("Downloading newer version...")

        result = self.network.download_document()

        return result["status"] == "OK"