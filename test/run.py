"""Headless check of Pole Tidy on vanilla, and over Powered Concrete's floor: python test/run.py [--with power-propagation]"""
from factorio_paths import main

main(__file__, {"pt-test": 140, "pt-floor": 140}, user_mods=("Powered_Concrete",))
