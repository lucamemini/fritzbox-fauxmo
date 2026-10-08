import hashlib
import logging
import os
import sys

import requests
from fauxmo.plugins import FauxmoPlugin


logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

logger = logging.getLogger("fritz_plugin")


class FritzDectPlugin(FauxmoPlugin):

    def __init__(
        self,
        *,
        name,
        port,
        fritz_host,
        ain,
    ):
        self.fritz_host = fritz_host
        self.ain = ain

        self.fritz_user = os.environ.get("FRITZ_USER")
        self.fritz_pass = os.environ.get("FRITZ_PASS")

        if not self.fritz_user:
            raise RuntimeError(
                "FRITZ_USER environment variable is not set"
            )

        if not self.fritz_pass:
            raise RuntimeError(
                "FRITZ_PASS environment variable is not set"
            )

        self._sid = None

        super().__init__(
            name=name,
            port=port,
        )

    def _login(self):
        logger.info(
            "[%s] Logging in to FRITZ!Box...",
            self.name,
        )

        r = requests.get(
            f"{self.fritz_host}/login_sid.lua",
            timeout=5,
        )
        r.raise_for_status()

        challenge = (
            r.text
            .split("<Challenge>")[1]
            .split("</Challenge>")[0]
        )

        md5 = hashlib.md5(
            f"{challenge}-{self.fritz_pass}".encode("utf-16le")
        ).hexdigest()

        response = f"{challenge}-{md5}"

        r = requests.get(
            f"{self.fritz_host}/login_sid.lua",
            params={
                "username": self.fritz_user,
                "response": response,
            },
            timeout=5,
        )
        r.raise_for_status()

        sid = (
            r.text
            .split("<SID>")[1]
            .split("</SID>")[0]
        )

        if sid == "0000000000000000":
            logger.error(
                "[%s] FRITZ!Box login failed",
                self.name,
            )
            raise RuntimeError(
                "FRITZ!Box login failed"
            )

        self._sid = sid

        logger.info(
            "[%s] Login successful",
            self.name,
        )

    def _call(self, switchcmd):

        for attempt in range(2):

            if not self._sid:
                self._login()

            r = requests.get(
                f"{self.fritz_host}/webservices/homeautoswitch.lua",
                params={
                    "switchcmd": switchcmd,
                    "ain": self.ain,
                    "sid": self._sid,
                },
                timeout=5,
            )

            if r.status_code == 403:
                logger.warning(
                    "[%s] SID expired, logging in again",
                    self.name,
                )

                self._sid = None
                continue

            r.raise_for_status()

            return r.text.strip()

        logger.error(
            "[%s] Unable to contact FRITZ!Box after 2 attempts",
            self.name,
        )

        raise RuntimeError(
            "Unable to contact FRITZ!Box"
        )

    def on(self):
        logger.info(
            "[%s] Turning ON (AIN=%s)",
            self.name,
            self.ain,
        )

        self._call("setswitchon")

        logger.info(
            "[%s] Successfully turned ON",
            self.name,
        )

        return True

    def off(self):
        logger.info(
            "[%s] Turning OFF (AIN=%s)",
            self.name,
            self.ain,
        )

        self._call("setswitchoff")

        logger.info(
            "[%s] Successfully turned OFF",
            self.name,
        )

        return True

    def get_state(self):
        state = self._call("getswitchstate")

        result = "on" if state == "1" else "off"

        logger.info(
            "[%s] State -> %s",
            self.name,
            result,
        )

        return result