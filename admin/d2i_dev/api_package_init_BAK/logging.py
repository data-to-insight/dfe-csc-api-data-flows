import logging
import sys

import logging
import sys



def setup_logging(name: str = None, level: int = logging.INFO, log_to_file: bool = False, filepath: str = "pipeline.log") -> logging.Logger:
    """
    Configure root or named logger with console and optional file output.

    Args:
        name: Logger name (default: root).
        level: Logging level (default: INFO).
        log_to_file: Whether to log to file.
        filepath: Path for log file if enabled.

    Returns:
        Configured logger instance.
    """
    logger = logging.getLogger(name)
    logger.setLevel(level)
    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")

    if not logger.handlers:
        # Console output
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)

        # Optional file output
        if log_to_file:
            file_handler = logging.FileHandler(filepath)
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)

    return logger