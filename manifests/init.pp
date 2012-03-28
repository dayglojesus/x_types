# Class: x_types
#
# This module manages x_types
#
# Parameters:
#
# Actions:
#
# Requires:
#
# Sample Usage:
#
# [Remember: No empty lines between comments and class definition]
class x_types {
    
  case $::macosx_productversion_major {
    "10.7": {
      if $::rubycocoa_version < 1.0.2 {
        fail("X_types module on Mac OS X Lion requires RubyCocoa 1.0.2 or better. See README for more details.")
      } # if
    } # 10.7
  } # case

}
