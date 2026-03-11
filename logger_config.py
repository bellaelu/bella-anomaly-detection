import logging

LOG_FILE = "app.log"

def setup_logger():
    logger = logging.getLogger("anomaly_pipeline")
    logger.setLevel(logging.INFO)

    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s"
    )

    # console logging
    console = logging.StreamHandler()
    console.setFormatter(formatter)

    # file logging
    file_handler = logging.FileHandler(LOG_FILE)
    file_handler.setFormatter(formatter)

    logger.addHandler(console)
    logger.addHandler(file_handler)

    return logger


logger = setup_logger()