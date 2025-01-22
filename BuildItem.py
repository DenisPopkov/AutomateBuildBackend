class BuildItem:
    def __init__(self, id, version, platform_name):
        self.id = id
        self.version = version
        self.platform_name = platform_name

    def to_dict(self):
        return {
            "id": self.id,
            "version": self.version,
            "platformName": self.platform_name
        }
