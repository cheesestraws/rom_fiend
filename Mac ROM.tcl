#### Macintosh DeclROM and System ROM format for Hex Fiend
# Copyright (c) 2022-2023 Eric Harmon

# Note: data types are described in the card manual, page 152

#### Hex Fiend setup

hf_min_version_required 2.15
big_endian

#### Detect scrambled ROMs

# TODO: We're not detecting all conditions, just the ones I've found
goto 2
set magic [uint32]
if {$magic == 0x38D46CA5} {
	entry "ERROR" "ROM must be byte-wise reversed and XOR'd with 0xFF"
	return
}

goto [expr [len]-6]
set magic [uint32]
if {$magic == 0x935AC72B} {
	entry "ERROR" "ROM must be byte-swapped from little-endian"
	return
} elseif {$magic == 0xA56CD438} {
	entry "ERROR" "ROM must be XOR'd with 0xFF"
	return
} elseif {$magic == 0x7878} {
	entry "ERROR" "ROM is repeated across bytelanes, take every 4th byte"
	return
}

# Reset state
goto 0

#### File matching

# Currently we don't require this, since we can parse System ROMs as well -- if it's not a DeclROM or a System ROM it'll be caught way below as unsupported
#requires [expr [len]-6] "5a 93 2b c7"

#### Functions

## Utility functions

# Add support for int24s
# TODO: A better way? Ultimately we want an int24 and HexFiend only supports uint24
# So we read the first part to get the signing information, then read the second part and bit shift everything into place
proc int24 {args} {
	set first [int16]
	set second [uint8]
	set value [expr $first << 8 | $second]
	if {[llength $args] > 0} {
		move -3
		entry [lindex $args 0] $value 3
		move 3
	}
	return $value
}

proc sort_dict_by_int_value {dict args} {
	set lst {}
	dict for {k v} $dict {lappend lst [list $k $v]}
	return [concat {*}[lsort -integer -index 1 {*}$args $lst]]
}

## Human readable text parsers

# Given raw byte lane data, translate to human readable
proc byte_lanes {input_lanes} {
	# TODO: Could we read bits instead of just hardcoding the documented table?
	switch $input_lanes {
		225 {
			# 0xE1
			set lanes "0"
		}
		210 {
			# 0xD2
			set lanes "1"
		}
		195 {
			# 0xC3
			set lanes "0,1"
		}
		180 {
			# 0xB4
			set lanes "2"
		}
		165 {
			# 0xA5
			set lanes "0,2"
		}
		150 {
			# 0x96
			set lanes "1,2"
		}
		135 {
			# 0x87
			set lanes "0,1,2"
		}
		120 {
			# 0x78
			set lanes "3"
		}
		105 {
			# 0x69
			set lanes "0,3"
		}
		90 {
			# 0x5A
			set lanes "1,3"
		}
		75 {
			# 0x4B
			set lanes "0,1,3"
		}
		60 {
			# 0x3C
			set lanes "2,3"
		}
		45 {
			# 0x2D
			set lanes "0,2,3"
		}
		30 {
			# 0x1E
			set lanes "1,2,3"
		}
		15 {
			# 0x0F
			set lanes "0,1,2,3"
		}
		default {
			set lanes "Unknown"
		}
	}
	return $lanes
}

# Given a resource type, return the human readable type
proc rsrc_type {input_type} {
	# Where possible, from ROMDefs.inc
	switch $input_type {
		1 {
			set type "Board"
		}
		2 {
			set type "Test"
		}
		3 {
			set type "Display"
		}
		4 {
			set type "Network"
		}
		6 {
			# TODO: Confirm
			set type "Communications"
		}
		8 {
			# Confusingly this is used for capture cards, etc
			# Per the docs, "scanners bring in data somehow"
			# TODO: Possible cTypes are 1 for....video?
			set type "Scanner"
		}
		9 {
			# TODO: Confirm, the Kanji board and WGS card use these, Kanji for ROM, WGS for Memory
			# TODO: Linux calls this "font" but I think they're wrong based on how WGS uses this
			set type "Memory"
		}
		10 {
			set type "CPU"
		}
		12 {
			# SCSI cards use this, but officially it's the "intelligent bus"
			set type "IntBus"
		}
		17 {
			set type "Proto"
		}
		19 {
			# TODO: The PC Drive card claims to be an "intelligent bus" but uses 19, so...let's assume for now this is the same for some reason
			set type "IntBus"
		}
		25 {
			# TODO: Confirm, Interware Video CD Player uses this for MPEG decoder, PowerVideo AV for JPEG decoder
			set type "Compression Accelerator(?)"
		}
		32 {
			# PowerBook Duo System page 184 (204)
			set type "Dock"
		}
		default {
			# TODO: Categories include display, network, terminal emulator, serial, parallel, intelligent bus, and human input devices.
			# TODO: The followng types may be correct:
			#  - 7: Printer controller? -- LasterMAX uses it
			#  - 12: Disk
			#  - 17: Debug Card?
			#  - 10: Floppy Disk?
			#  		- With cType 2 for MFM?
			set type "Unknown"
		}
	}
	return $type
}

# Resolve cTypes to human readable
proc resolve_ctype {category ctype} {
	switch $category {
		1 {
			# Board always seems to be zero, so just call that...Board
			switch $ctype {
				0 {
					# Cards page 148
					set type "Board (0)"
				}
				default {
					set type "Unknown ($ctype)"
				}
			}
		}
		3 {
			# Validated by looking at Display cards
			switch $ctype {
				1 {
					set type "Video (1)"
				}
				2 {
					# Cards page 148
					set type "LCD (2)"
				}
				5 {
					# Aapps MicroTV
					set type "TV (5)"
				}
				default {
					set type "Unknown ($ctype)"
				}
			}
		}
		4 {
			# Validated by looking at Ethernet cards
			switch $ctype {
				1 {
					set type "EtherNet (1)"
				}
				2 {
					# TODO: Linux claims this is RS232, but TokenTalk seems correct since the TokenRing card uses it
					set type "TokenTalk (2)"
				}
				7 {
					set type "Token Ring 802.2? (4)"
				}
				default {
					# Possible others:
					# AppleTalk
					# DECNet
					set type "Unknown ($ctype)"
				}
			}
		}
		6 {
			# Validated by looking at Communications cards
			switch $ctype {
				2 {
					set type "RS232 (2)"
				}
				6 {
					# VersaLink
					set type "RS422 (6)"
				}
				8 {
					# Referenced by TattleTech and the Mac Mainframe II
					set type "IBM 3270 (8)"
				}
				11 {
					set type "Centronics (11)"
				}
				27 {
					# SCii RNIS
					set type "ISDN (27)"
				}
				default {
					# Possible others:
					# Parallel
					# MIDI
					# 3270
					# 5250
					set type "Unknown ($ctype)"
				}
			}
		}
		8 {
			# TODO: 1 is Video digitizer and 2 is Audio?
			# Scanner
			# Image Digitizer
			# Audio Signal Processor
			# Optical Scanner
			set type "Unknown ($ctype)"
		}
		10 {
			switch $ctype {
				1 {
					# Card docs page 173
					set type "68000 (1)"
				}
				2 {
					# Guess, by process of elimination above and below
					set type "68010 (2)"
				}
				3 {
					# Linux nubus.h -- also present in Apple headers but ambiguously
					set type "68020 (3)"
				}
				4 {
					# Linux nubus.h -- also present in Apple headers but ambiguously
					set type "68030 (4)"
				}
				5 {
					# Radius Rocket
					set type "68040 (5)"
				}
				20 {
					# Team ASA Raven
					set type "i860 (20)"
				}
				21 {
					set type "AppleII (21)"
				}
				36 {
					# Reply Houdini II
					set type "80486 (36)"
				}
				default {
					# Possible others:
					# 68010
					# 8086
					# 80286
					# 80386
					set type "Unknown ($ctype)"
				}
			}
		}
		12 {
			# Validated by looking at PLI card
			switch $ctype {
				8 {
					set type "SCSI (8)"
				}
				default {
					set type "Unknown ($ctype)"
				}
			}
		}
		19 {
			# PC Drive card
			# TODO: Confirm
			switch $ctype {
				2 {
					set type "MFM (2)"
				}
				default {
					set type "Unknown ($ctype)"
				}
			}
		}
		25 {
			# TODO: These are a guess based on Interware cards
			switch $ctype {
				257 {
					set type "JPEG (257)"
				}
				259 {
					set type "MPEG (259)"
				}
				default {
					set type "Unknown ($ctype)"
				}
			}
		}
		32 {
			# PowerBookDuo System page 184 (204)
			switch $ctype {
				1 {
					set type "Dock Station (1)"
				}
				2 {
					set type "Dock Desk (2)"
				}
				3 {
					set type "Dock Travel (3)"
				}
			}
		}
		default {
			set type "Unknown ($ctype)"
		}
	}
	return $type
}

# Resolve drSW to human readable
proc resolve_drsw {drSW} {
	switch $drSW {
		1 {
			set type "Apple (1)"
		}
		65535 {
			# Card docs page 173
			set type "Not in ROM (65535)"
		}
		default {
			# TODO: These were assigned by Apple so we can encode known ones
			set type "$drSW"
		}
	}
}

# Given a CPU type, return the human readable type
proc cpu_type {input_type} {
	# NuBus reference page 167 (208)
	# ROMDefs.h for PPC
	switch $input_type {
		1 {
			set type "68000 (1)"
		}
		2 {
			set type "68020 (2)"
		}
		3 {
			set type "68030 (3)"
		}
		4 {
			set type "68040 (4)"
		}
		37 {
			# TODO: This might be for CPU sResources and not drivers?
			set type "PowerPC 601 (37)"
		}
		46 {
			# TODO: This might be for CPU sResources and not drivers?
			set type "PowerPC 603 (46)"
		}
		default {
			set type "Unknown ($input_type)"
		}
	}
	return $type
}

# Convert timing map values to human readable
proc timing_map {timing} {
	# TODO: Add all the timings from Video.h
	# TODO: Also see DeclData.r...what are those sName for?
	switch $timing {
		0 {
			# TODO: zero entry is a bit unclear: "Unknown timing... force user to confirm."
			set type "User Specified(?) (0)"
		}
		8 {
			set type "Thunder/24 (Buggy) (8)"
		}
		42 {
			set type "Fixed Rate LCD (42)"
		}
		130 {
			set type "512x384 (60 Hz) (130)"
		}
		140 {
			set type "640x480 (67 Hz) (140)"
		}
		160 {
			set type "640x870 (75 Hz) (160)"
		}
		170 {
			set type "832x624 (75 Hz) (170)"
		}
		210 {
			set type "1024x768 (75 Hz) (210)"
		}
		220 {
			set type "1152x870 (75 Hz) (220)"
		}
		230 {
			set type "\[NTSC\] 512x384 (60 Hz, interlaced, non-convolved) (230)"
		}
		232 {
			set type "\[NTSC\] 640x480 (60 Hz, interlaced, non-convolved) (232)"
		}
		238 {
			set type "\[PAL\] 640x480 (50 Hz, interlaced, non-convolved) (238)"
		}
		240 {
			set type "\[PAL\] 768x576 (50 Hz, interlaced, non-convolved) (240)"
		}
		280 {
			set type "1600x1200 (60 Hz) (280)"
		}
		510 {
			set type "1920x1080 (60 Hz) (510)"
		}
		default {
			set type "Unknown ($timing)"
		}
	}
	return $type
}

# Parse block transfer bit tables into human readable
proc parse_transfer_bits {} {
	uint16_bits 0 "2-bit Transfer Supported"
	move -2
	uint16_bits 1 "4-bit Transfer Supported"
	move -2
	uint16_bits 2 "8-bit Transfer Supported"
	move -2
	uint16_bits 3 "16-bit Transfer Supported"
}


## sResource type parsers

# Compute the vendor info
proc vendor_info {offset} {
	set temp_location [pos]
	move $offset
	section "Vendor Info"
	set vendor_rsrc_offset 0x01
	set vendor_rsrc_type 0x00
	while {[expr $vendor_rsrc_offset != 0x000000 && $vendor_rsrc_type != 0xFF]} {
		section "Metadata"
		sectioncollapse
		set vendor_rsrc_type [uint8 "Type"]
		set vendor_rsrc_offset [int24 "Offset"]
		endsection
		set vendor_rsrc_entry_return [pos]
		move [expr $vendor_rsrc_offset-4]
		# NuBus documentation, page 178 (219)
		switch $vendor_rsrc_type {
			1 {
				cstr "macroman" "VendorID"
			}
			2 {
				cstr "macroman" "SerialNum"
			}
			3 {
				cstr "macroman" "RevLevel"
			}
			4 {
				cstr "macroman" "PartNum"
			}
			5 {
				cstr "macroman" "Date"
			}
		}
		goto $vendor_rsrc_entry_return
	}
	goto $temp_location
	endsection
}

# Examine a driver directory for directoriesdata
proc driver_dir {offset} {
	set temp_location [pos]
	move $offset
	section "Drivers"
	set driver_rsrc_offset 0x01
	set driver_rsrc_type 0x00
	while {[expr $driver_rsrc_offset != 0x000000 && $driver_rsrc_type != 0xFF]} {
		section "Driver"
		set driver_rsrc_type [uint8]
		set decoded_cpu [cpu_type $driver_rsrc_type]
		sectionname "Driver ($driver_rsrc_type)"
		move -1
		entry "CPU ID" $decoded_cpu 1
		move 1
		set driver_rsrc_offset [int24 "Offset"]
		if {$driver_rsrc_type == 0xFF} {
			sectionname "Terminator (255)"
			sectioncollapse
		} else {
			# TODO: Not sure this extraction is correct, or at least it's insufficient
			# "For the Macintosh Operating System, this structure is described in detail with the Device Manager information in Inside Macintosh."
			# Inside Macintosh, Device Manager page 1-13
			set driver_rsrc_entry_return [pos]
			move -4
			move $driver_rsrc_offset
			move 1
			set driver_length [uint24 "Physical Block Size"]
			# TODO: Assuming we subtract 4 because the length includes the header where the length is specified
			#bytes [expr $driver_length-4] "Driver Data"
			section "Driver Data"
			section "Header"
			sectioncollapse
			set driver_region_start [pos]
			uint16 "drvrFlags"
			uint16 "drvrDelay"
			uint16 "drvrEMask"
			uint16 "drvrMenu"
			set open_offset [uint16 "drvrOpen"]
			set prime_offset [uint16 "drvrPrime"]
			set control_offset [uint16 "drvrCtl"]
			set status_offset [uint16 "drvrStatus"]
			set close_offset [uint16 "drvrClose"]
			set name_length [uint8 "drvrName Length"]
			if {$name_length > 0} {
				set name [str $name_length "macroman" "drvrName"]
			} else {
				set name "Unknown"
			}
			endsection

			section "Functions"
			# The driver functions can appear in any order, or be omitted entirely (offset == 0), so to determine the size of each function block (approximately)
			# we have to sort all the offsets to determine the order of the function calls, 
			set offset_dict [dict create "Open" $open_offset "Prime" $prime_offset "Control" $control_offset "Status" $status_offset "Close" $close_offset]
			set sorted_offsets [sort_dict_by_int_value $offset_dict]
			set current_offset 0
			set current_type ""
			dict for {type value} $sorted_offsets {
				if {$value > 0} {
					if {$current_offset > 0} {
						goto $driver_region_start
						move $current_offset
						# TODO: We can read right off the edge so catch errors
						set status [catch {
							bytes [expr $value-$current_offset] $current_type
						} err]
						if {$status} {
							entry "ERROR" $err
						}
						# Debugging:
						#entry $current_type "$value - $current_offset"
					}
					set current_type $type
					set current_offset $value
				}
			}
			# For the last entry, it must span from the $current_offset to the $driver_length
			if {$current_offset > 0} {
					goto $driver_region_start
					move $current_offset
					# TODO: Is this _really_ correct? It seems to work but this is ugly -- we're just compensating for offset mistakes earlier
					# TODO: We seem to get Micron driver wrong still, so there's more work to do -- it's possible this is NEVER exact, because the OS doesn't care as long as the entry points work
					# TODO: Sometimes we read right off the end of the file (Spectrum 8 Series III), so catch errors
					set status [catch {
						bytes [expr $driver_length-4-$current_offset+12] $current_type
					} err]
					if {$status} {
						entry "ERROR" $err
					}
					# Debugging:
					#entry $current_type "$value - $current_offset"
			}
			endsection
			endsection
			sectionname "Driver ($driver_rsrc_type) ($name)"
			goto $driver_rsrc_entry_return
		}
		endsection
	}
	goto $temp_location
	endsection
}

# Examine the gamma data
proc gamma_dir {offset} {
	set temp_location [pos]
	move $offset
	set gamma_rsrc_offset 0x01
	set gamma_rsrc_type 0x00
	while {[expr $gamma_rsrc_offset != 0x000000 && $gamma_rsrc_type != 0xFF]} {
		section "Gamma Entry"
		sectioncollapse
		set gamma_rsrc_type [uint8 "Type"]
		set gamma_rsrc_offset [int24 "Offset"]
		if {$gamma_rsrc_type == 0xFF} {
			sectionname "Terminator (255)"
		} else {
			# TODO: Something is weird, sometimes we get bad entries with nonsense offsets
			set gamma_rsrc_entry_return [pos]
			move [expr $gamma_rsrc_offset-4]
			set start [pos]
			set length [uint32 "Record Length"]
			uint16 "ID"
			set name [cstr "macroman" "Name"]
			sectionname $name
			set end [pos]
			bytes [expr $length - ($end - $start)] "Gamma Image"
			goto $gamma_rsrc_entry_return
		}
		endsection
	}
	goto $temp_location
}

# Examine the sVidParm data
proc svidparam_dir {offset} {
	set temp_location [pos]
	move $offset
	set svidparam_rsrc_offset 0x01
	set svidparam_rsrc_type 0x00
	while {[expr $svidparam_rsrc_offset != 0x000000 && $svidparam_rsrc_type != 0xFF]} {
		section "Vid Param"
		sectioncollapse
		set svidparam_rsrc_type [uint8 "Type"]
		sectionname "Video Mode $svidparam_rsrc_type"
		set svidparam_rsrc_offset [int24 "Offset"]
		if {$svidparam_rsrc_type == 0xFF} {
			sectionname "Terminator (255)"
		} else {
			set meh [pos]
			# TODO: Isn't this off by 4?
			move $svidparam_rsrc_offset
			uint32 "TODO"
			goto $meh
		}
		endsection
	}
	goto $temp_location
}

proc smemory {offset} {
	set temp_location [pos]
	move $offset
	set smemory_rsrc_offset 0x01
	set smemory_rsrc_type 0x00
	while {[expr $smemory_rsrc_offset != 0x000000 && $smemory_rsrc_type != 0xFF]} {
		section "sMemory Entry"
		sectioncollapse
		set smemory_rsrc_type [uint8 "Type"]
		set smemory_rsrc_offset [int24 "Offset"]
		switch $smemory_rsrc_type {
			1 {
				# TODO: This is redundant with the other sRsrcType parse, should be merged
				# TODO: Is category "150" just "Memory"?
				sectionname "sRsrcType (1)"
				set temp [pos]
				move -4
				move $smemory_rsrc_offset
				set category [uint16]
				move -2
				entry "Category" [rsrc_type $category] 2
				move 2
				# TODO: "The cType field is a subclass within a category. Within display devices, for example, are video cards and graphics extension processors; within networks, AppleTalk and Ethernet."
				# TODO: So we should categorize the resources correctly based on the top-level Category.
				set ctype [uint16]
				move -2
				entry "cType" [resolve_ctype $category $ctype] 2
				move 2
				set drSW [uint16]
				move -2
				entry "DrSW" [resolve_drsw $drSW] 2
				move 2
				# This *should* be non-unique across smemorys, so we can't do anything but list the number
				uint16 "DrHW"
				goto $temp
			}
			2 {
				set smemory_rsrc_entry_return [pos]
				move [expr $smemory_rsrc_offset-4]
				set name [cstr "macroman" "Name"]
				sectionname "sRsrcName (2)"
				goto $smemory_rsrc_entry_return
			}
			128 {
				sectionname "MinorRAMAddr (128)"
				entry "TODO" 0
				# TODO
			}
			129 {
				sectionname "MajorRAMAddr (129)"
				entry "TODO" 0
				# TODO
			}
			130 {
				sectionname "MinorROMAddr (130)"
				entry "TODO" 0
				# TODO
			}
			131 {
				sectionname "MajorROMAddr (131)"
				entry "TODO" 0
				# TODO
			}
			132 {
				sectionname "MinorDeviceAddr (132)"
				entry "TODO" 0
				# TODO
			}
			133 {
				sectionname "MajorDeviceAddr (133)"
				entry "TODO" 0
				# TODO
			}
			255 {
				sectionname "Terminator (255)"
			}
			default {
				sectionname "Unknown ($smemory_rsrc_type)"
			}
		}
		endsection
	}
	goto $temp_location
}

# Discover the video mode names
proc vid_names {offset} {
	set temp_location [pos]
	move $offset
	set vid_names_rsrc_offset 0x01
	set vid_names_rsrc_type 0x00
	while {[expr $vid_names_rsrc_offset != 0x000000 && $vid_names_rsrc_type != 0xFF]} {
		section "Video Mode"
		sectioncollapse
		set vid_names_rsrc_type [uint8 "Type"]
		set vid_names_rsrc_offset [int24 "Offset"]
		# TODO: Does this mean something else?
		if {$vid_names_rsrc_type == 0} {
			sectionname "Invalid (0)"
		} elseif {$vid_names_rsrc_type == 0xFF} {
			sectionname "Terminator (255)"
		} else {
			set vid_names_rsrc_entry_return [pos]
			move [expr $vid_names_rsrc_offset-4]
			uint32 "Record Length"
			# TODO: Confirm
			uint16 "Localization ID"
			set name [cstr "macroman" "Name"]
			sectionname $name
			goto $vid_names_rsrc_entry_return
		}
		endsection
	}
	goto $temp_location
}

# Discover the video modes
proc vid_mode {offset} {
	set temp_location [pos]
	move $offset
	set vid_mode_rsrc_offset 0x01
	set vid_mode_rsrc_type 0x00
	while {[expr $vid_mode_rsrc_offset != 0x000000 && $vid_mode_rsrc_type != 0xFF]} {
		section "Metadata"
		sectioncollapse
		set vid_mode_rsrc_type [uint8 "Type"]
		set vid_mode_rsrc_offset [int24 "Offset"]
		set vid_mode_rsrc_entry_return [pos]
		endsection
		move -4
		# NuBus documentation, page 178 (219)
		switch $vid_mode_rsrc_type {
			1 {
				# TODO: Properly mark out this offset
				move $vid_mode_rsrc_offset
				section "Mode Data"
				uint32 "Record Size"
				uint32 "vpBaseOffset"
				uint16 "vpRowBytes"
				uint16 "vpBounds(0)"
				uint16 "vpBounds(1)"
				uint16 "vpBounds(2)"
				uint16 "vpBounds(3)"
				uint16 "vpVersion"
				uint16 "vpPackType"
				# Table 9-2 is incorrect, this is a full byte
				uint32 "vpPackSize"
				# TODO: Decode these properly instead of leaving fixed-point hex
				uint32 -hex "vpHRes"
				uint32 -hex "vpVRes"
				uint16 "vpPixelType"
				uint16 "vpPixelSize"
				uint16 "vpCmpCount"
				uint16 "vpCmpSize"
				uint32 "vpPlaneBytes"
				endsection
			}
			2 {
				# TODO: mTable: Offset to the device color table for fixed CLUT devices; mTable has the same format as the cTabHandle structure, described with the Color Manager information in Inside Macintosh.
				uint32 "mTable Offset"
			}
			3 {
				move 1
				uint24 "Page Count"
			}
			4 {
				move 1
				uint24 "Device Type"
			}
			# TODO: Confirm
			5 {
				move 1
				# From ROMDefs.h: slot block xfer info PER MODE
				uint24 "mBlockTransferInfo"
			}
			# TODO: Confirm
			6 {
				move 1
				# From ROMDefs.h: slot max. locked xfer count PER MODE
				uint24 "mMaxLockedTransferCount"
			}
			default {
				# TODO: Mark terminator
			}
		}
		goto $vid_mode_rsrc_entry_return
	}
	goto $temp_location
}

# Examine a block describing an executable section
proc exec_block {offset} {
	# TODO: Need to verify this block is correct
	set temp_location [pos]
	move $offset
	set length [uint32 "Length"]
	uint8 "Revision"
	set raw_cpu [uint8]
	move -1
	entry "CPU ID" [cpu_type $raw_cpu] 1
	move 4
	set second_offset [int24 "Offset"]
	move -4

	move $second_offset
	# TODO: This calculation is WEIRD, but it seems correct?
	bytes [expr $length-$second_offset-8] "Code"
	goto $temp_location
}

# Read the auxiliary video parameters
proc vid_aux_params {offset} {
	set temp_location [pos]
	move $offset
	set vid_aux_params_rsrc_offset 0x01
	set vid_aux_params_rsrc_type 0x00
	while {[expr $vid_aux_params_rsrc_offset != 0x000000 && $vid_aux_params_rsrc_type != 0xFF]} {
		section "Mode"
		sectioncollapse
		section "Metadata"
		sectioncollapse
		set vid_aux_params_rsrc_type [uint8 "Type"]
		set vid_aux_params_rsrc_offset [int24 "Offset"]
		endsection
		if {$vid_aux_params_rsrc_type == 0xFF} {
			sectionname "Terminator (255)"
		} else {
			sectionname "Mode $vid_aux_params_rsrc_type"
			set vid_aux_params_rsrc_entry_return [pos]
			move [expr $vid_aux_params_rsrc_offset-4]
			uint32 "Unknown"
			set timing_info [uint32]
			move -4
			entry "Timing" [timing_map $timing_info] 4
			goto $vid_aux_params_rsrc_entry_return
		}
		endsection
	}
	goto $temp_location
}

# Examine the block transfer info block
proc block_transfer_info {offset} {
	set temp_location [pos]
	move $offset
	section "Master"
	# Master word
	uint16_bits 15 "Is Master"
	move -2
	uint16_bits 14 "Locked Transfer Supported"
	move -2
	# TODO: This is 'Reserved' so technically we don't need to parse it, but we should be reading the bit values
	#uint16_bits 4,5,6 "Format"
	#move -2
	parse_transfer_bits
	endsection
	section "Slave"
	# Slave word
	uint16_bits 15 "Is Slave"
	move -2
	parse_transfer_bits
	endsection
	goto $temp_location
}

# Parse the sResourceDir
proc parse_rsrc_dir {directory} {
	# Jump into the directory and start parsing it's entries
	goto $directory
	set rsrc_offset 1
	set rsrc_type 0

	# Loop over the top level sResource entries
	while {[expr $rsrc_offset != 0x000000 && $rsrc_type != 0xFF]} {
		section "sResource"
		sectioncollapse

		# These will be filed in by the type record, which is usually first
		# TODO: If it's not before the video entries, we won't parse them correctly
		set category 0
		set ctype 0
		set drSW 0
		set rsrc_name ""
		
		section "Metadata"
		sectioncollapse
		set rsrc_type [uint8 "Type"]
		set rsrc_offset [int24]
		endsection
		set location [pos]
		if {$rsrc_type == 0xFF} {
			sectionname "Terminator (255)"
		} else {
			move [expr $rsrc_offset-4]

			set sub_rsrc_offset 0x01
			set sub_rsrc_type 0x00
			set human_category "" 

			# Loop over the sResources in this entry
			while {[expr $sub_rsrc_offset != 0x000000 && $sub_rsrc_type != 0xFF]} {
				section "sRsrc"
				sectioncollapse
				section "Metadata"
				set sub_rsrc_type [uint8 "Type"]
				set sub_rsrc_offset [int24]
				sectioncollapse
				endsection
				set reset_location [pos]
				move -4
				# We are now at the proper location to add $sub_rsrc_offsets.
				# The location will be reset automatically after the switch to continue looping.

				# TODO: Sometimes this error handling doesn't pop us out enough sections
				set status [catch {
					# See NuBus documentation, page 164 (205), also page 185 (226)
					switch -glob $sub_rsrc_type {
						1 {
							# See NuBus documentation, page 165 (206)
							sectionname "sRsrcType (1)"
							move $sub_rsrc_offset
							# TODO: remove bit 31: "bit 31 is reserved for Apple's use" -- page 145
							set category [uint16]
							move -2
							set human_category [rsrc_type $category]
							entry "Category" "$human_category ($category)" 2
							move 2
							set ctype [uint16]
							move -2
							entry "cType" [resolve_ctype $category $ctype] 2
							move 2
							set drSW [uint16]
							move -2
							entry "DrSW" [resolve_drsw $drSW] 2
							move 2
							# This *should* be non-unique across vendors, so we can't do anything but list the number
							uint16 "DrHW"
						}
						2 {
							sectionname "sRsrcName (2)"
							move $sub_rsrc_offset
							set rsrc_name [cstr "macroman" "Name"]
						}
						3 {
							sectionname "sRsrcIcon (3)"
							# TODO: Is this the correct offset?
							move $sub_rsrc_offset
							# Size per cards documentation, page 184 (225)
							bytes 128 "Icon"
						}
						4 {
							sectionname "sRsrcDrvrDir (4)"
							driver_dir $sub_rsrc_offset
						}
						5 {
							# Card page 167
							sectionname "sRsrcLoadRec (5)"
							exec_block $sub_rsrc_offset
						}
						6 {
							# Card page 168
							sectionname "sRsrcBootRec (6)"
							exec_block $sub_rsrc_offset
						}
						7 {
							sectionname "sRsrcFlags (7)"
							move 2
							# TODO: is that "sResource flags for sRsrc_Flags" in ROMDefs.h?
							# Card manual page page 169
							uint16_bits 1 "fOpenAtStart"
							move -2
							uint16_bits 2 "f32BitMode"
						}
						8 {
							sectionname "sRsrcHWDevld (8)"
							move 1
							entry "Hardware Device ID" $sub_rsrc_offset 3
						}
						10 {
							sectionname "MinorBaseOS (10)"
							move $sub_rsrc_offset
							uint32 "minBaseOS"
						}
						11 {
							sectionname "MinorLength (11)"
							move $sub_rsrc_offset
							uint32 "minorLength"
						}
						12 {
							sectionname "MajorBaseOS (12)"
							move $sub_rsrc_offset
							uint32 "majBaseOS"
						}
						13 {
							sectionname "MajorLength (13)"
							move $sub_rsrc_offset
							uint32 "majorLength"
						}
						14 {
							# from ROMDefs.h: sBlock diagnostic code
							sectionname "sRsrcTest (14)"
							entry "TODO" 0
							# TODO: Parse
						}
						15 {
							sectionname "sRsrcCicn (15)"
							entry "TODO" 0
							# Card documentation page 185 (226)
							# TODO: Parse
						}
						16 {
							# Card documentation page 170 (211)
							sectionname "sRsrclcl8 (16)"
							move $sub_rsrc_offset
							# Equivalent to icl8 at 32x32 so fixed at 1024
							bytes 1024 "Icon"
						}
						17 {
							# Card documentation page 171 (212)
							sectionname "sRsrclcl4 (17)"
							move $sub_rsrc_offset
							# Equivalent to icl4 at 32x32 so fixed at 512
							bytes 512 "Icon"
						}
						20 {
							# From ROMDefs.h: general slot block xfer info
							# Card book page 181 (222)
							sectionname "sBlockTransferInfo (20)"
							block_transfer_info $sub_rsrc_offset
						}
						21 {
							# From ROMDefs.h: slot max. locked xfer count
							sectionname "sMaxLockedTransferCount (21)"
							move $sub_rsrc_offset
							uint32 "Maximum Locked Transfers"
						}
						32 {
							sectionname "BoardID (32)"
							move 1
							entry "Board ID" [expr $sub_rsrc_offset & 0xFF] 3
						}
						33 {
							sectionname "PRAMInitData (33)"
							# TODO: Might be broken
							move $sub_rsrc_offset
							move 1
							uint24 "Physical Block Size"
							move 2
							uint8 "Byte 1"
							uint8 "Byte 2"
							uint8 "Byte 3"
							uint8 "Byte 4"
							uint8 "Byte 5"
							uint8 "Byte 6"
						}
						34 {
							sectionname "PrimaryInit (34)"
							exec_block $sub_rsrc_offset
						}
						35 {
							sectionname "STimeOut (35)"
							move 1
							uint24 "Time Out"
						}
						36 {
							sectionname "VendorInfo (36)"
							vendor_info $sub_rsrc_offset
						}
						37 {
							# TODO: Confirm
							# From ROMDefs.h: Board Flags
							sectionname "BoardFlags (37)"
							entry "TODO" 0
							# TODO: Parse
						}
						38 {
							sectionname "SecondaryInit (38)"
							exec_block $sub_rsrc_offset
						}
						64 {
							sectionname "sGammaDir (54)"
							gamma_dir $sub_rsrc_offset
						}
						65 {
							sectionname "sRsrcVidNames (65)"
							vid_names $sub_rsrc_offset
						}
						80 {
							# From ROMDefs.h: spID for Docking Handlers
							sectionname "sRsrcDock (80)"
							entry "TODO" 0
							# TODO: Parse
						}
						85 {
							# From ROMDefs.h: spID for board diagnostics
							sectionname "sDiagRec (85)"
							entry "TODO" 0
							# TODO: Parse
						}
						108 {
							sectionname "sMemory (108)"
							smemory $sub_rsrc_offset
						}
						123 {
							# From ROMDefs.h: more video info for Display Manager -- timing information
							sectionname "sVidAuxParams (123)"
							vid_aux_params $sub_rsrc_offset
						}
						124 {
							# From ROMDefs.h: DatLstEntry for debuggers indicating video anamolies
							sectionname "sDebugger (124)"
							entry "TODO" 0
							# TODO: Parse
						}
						125 {
							# From ROMDefs.h: video attributes data field (optional,word)
							sectionname "sVidAttributes (125)"
							move 2
							# fLCDScreen bit 0 - when set is LCD, else is CRT
							uint16_bits 0 "fLCDScreen"
							move -2
							# fBuiltInDisplay 1 - when set is built-in (in the box) display, else not
							uint16_bits 1 "fBuiltInDisplay"
							move -2
							# fDefaultColor 2 - when set display prefers multi-bit color, else gray
							uint16_bits 2 "fDefaultColor"
							move -2
							# fActiveBlack 3 - when set black on display must be written, else display is naturally black
							uint16_bits 3 "fActiveBlack"
							move -2
							# fDimMinAt1 4 - when set should dim backlight to level 1 instead of 0
							uint16_bits 4 "fDimAt1"
							# TODO.....two 4th bits???
							# fBuiltInDetach 4 - when set is built-in (in the box), but detaches
						}
						126 {
							# From ROMDefs.h
							# From card docs page 186
							# TODO: No, it's not on page 186?
							sectionname "sVidParmDir (126)"
							svidparam_dir $sub_rsrc_offset
						}
						140 {
							# From ROMDefs.h: directory of backlight tables
							sectionname "sBkltParmDir (140)"
							entry "TODO" 0
							# TODO: Parse
						}
						255 {
							sectionname "Terminator (255)"
						}
						"xxxxx" {
							# TODO: Disabled, this attempts to parse some SuperMac video data in the 2xx ID range, but does not work currently
							# TODO: 253, 254 don't conform to this format
							#{(20[0-9]|2[1-4][0-9]|25[0-4])} {}
							# TODO: Hax hax hax for SuperMac
							sectionname "$sub_rsrc_type ?????"
							move $sub_rsrc_offset
							uint32 "ID???"
							uint16 -hex "Flags??"
							uint16 -hex "Flags??"
							# TODO: Always 5002??
							#uint16 -hex "?????"
							move 2
							# TODO: Always 0600??
							#uint16 -hex "?????"
							move 2
							# TODO: Always 4F010??
							#uint16 -hex "?????"
							move 2
							# TODO: Always 0101??
							#uint16 -hex "?????"
							move 2
							# TODO: Always 000F??
							#uint16 -hex "?????"
							move 2
							uint16 -hex "Flags??"
							uint16 -hex "Flags??"
							uint16 "ID???"
							# TODO: Always 0002???
							#uint16 -hex "?????"
							move 2
							uint16 "ID???"
							uint16 "VBlank-related??"
							uint16 "VBlank-related??"
							# TODO: Always FFFF???
							#uint16 "?????"
							move 2
							# TODO: Always FFFF???
							#uint16 "?????"
							move 2
							uint16 -hex "Gamma????"
							# TODO: Always FFFF???
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always FFFF???
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always 0040?
							#uint16 "?????"
							move 2
							uint16 -hex "Flags??"
							# TODO: Always 0551?
							#uint16 "?????"
							move 2
							# TODO: Always 8005?
							#uint16 "?????"
							move 2
							# TODO: Always 0500?
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always E0C0?
							#uint16 "?????"
							move 2
							# TODO: Always B576?
							#uint16 "?????"
							move 2
							# TODO: Always 256D?
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							# TODO: Always 0081?
							#uint16 "?????"
							move 2
							# TODO: Always 0073?
							#uint16 "?????"
							move 2
							# TODO: Always zero
							#uint16 "?????"
							move 2
							uint16 "HRes"
							uint16 "VRes"
							uint16 -hex "Flags??"
							cstr macroman "Name"
						}
						default {
							sectionname "Unknown ($sub_rsrc_type)"
						}
					}
					# Process the special types for certain devices
					if {$sub_rsrc_type >= 128 && $sub_rsrc_type != 255} {
						if {$category == 3 && $drSW == 1} {
							# TODO: It's possible other software types use this same storage, but type 1 indicates: "For example, under Category Display and cType Video atypical predefined driver software interface would be one defined by Apple to work with QuickDraw using the Macintosh Operating System frame buffers." -- page 146
							sectionname "Video Mode ($sub_rsrc_type)"
							vid_mode $sub_rsrc_offset
						} elseif {$category == 4 && $ctype == 1 && $sub_rsrc_type == 128} {
							# TODO: This only seems to apply for resource type 128...what do the others do?
							sectionname "Ethernet Address ($sub_rsrc_type)"
							move $sub_rsrc_offset
							# Compute 48-bit address
							set first [uint32]
							set second [uint16]
							set mac [expr $first << 16 | $second]
							move -6
							entry "MAC" [format 0x%010x $mac] 6
						} elseif {$category == 10} {
							# ROMDefs.inc references these for CPU sResources
							# TODO: Is this really right?
							switch $sub_rsrc_type {
								129 {
									sectionname "MajRAMSp (128)"
									entry "TODO" 0
								}
								130 {
									sectionname "MinROMSp (129)"
									entry "TODO" 0
								}
							}
						}
					}
				} err]
				if {$status} {
					sectionvalue "ERROR"
					entry "ERROR" $err 1
					# TODO: Sometimes we haven't started a section when we error which causes us to crash anyway -- need to fix that we don't over-close sections
					#endsection
				}
				goto $reset_location
				endsection
			}
			if {$rsrc_type < 127} {
				set human_category "Board"
			}
			if {$rsrc_name != ""} {
				sectionname "$human_category \[$rsrc_name\] ($rsrc_type)"
			} else {
				sectionname "$human_category ($rsrc_type)"
			}
			goto $location
		}
		endsection
	}
}

#### Main parser

## Stage 1: DeclROM

set dir_start -1

if {$magic == 0x5A932BC7} {
	section "DeclROM"
	sectioncollapse

	# Jump to the end where the header is
	move [len]

	# Step backwards through the header
	move -1
	set raw_lanes [uint8]
	move -1
	entry "ByteLanes" [byte_lanes $raw_lanes] 1
	move 1
	move -6
	hex 4 "TestPattern"
	move -5
	uint8 "Format"
	move -2
	uint8 "RevisionLevel"
	move -5
	hex 4 "CRC"
	move -8
	set length [uint32 "Length"]

	move -7
	set offset [int24 "DirectoryOffset"]
	set dir_start [expr [len] - 20 + $offset]
	move -3
	entry "(Computed Directory Start)" $dir_start 3
	move 3

	section "Directory"
	parse_rsrc_dir $dir_start
	endsection
	endsection
}

## Stage 2: Extended DeclROM

goto [expr [len]-24]
set extended_magic [uint32]
if {$extended_magic == 0x5A932BC7} {
	section "Extended DeclROM"
	sectioncollapse
	move -4
	hex 4 "TestPattern"
	move -11
	set offset [int24 "Super DirectoryOffset"]
	set superdir_start [expr [len] - 32 + $offset]
	move -3
	entry "(Computed Directory Start)" $superdir_start 3
	move -4

	section "SuperInit"
	sectioncollapse
	section "Metadata"
	sectioncollapse
	set offset [int24 "Offset"]
	endsection
	exec_block [expr $offset-4]
	endsection

	goto $superdir_start
	# This is an sResource of pointers to sResource directories for each board
	# Loop over the top level sResource entries
	set rsrc_offset 1
	set rsrc_type 0
	while {[expr $rsrc_offset != 0x000000 && $rsrc_type != 0xFF]} {
		section "sRsrcDir"

		section "Metadata"
		sectioncollapse
		set rsrc_type [uint8 "Type"]
		set rsrc_offset [int24 "Offset"]
		endsection
		if {$rsrc_type == 0xFF} {
			sectionname "Terminator (255)"
		} else {
			sectionname "Directory ($rsrc_type)"
			# TODO: This is dumb
			set oldpos [pos]
			move -4
			move $rsrc_offset
			parse_rsrc_dir [pos]
			goto $oldpos
		}
		endsection
	}
	endsection
}

## Stage 3: System ROM

# TODO: This isn't quite right with Extended Format
if {$dir_start != 0} {
	# If we didn't find a DeclROM, then it has to be a System ROM, or it's not a supported file type
	if {$dir_start == -1} {
		requires 6 "00 2a"
	}
	# Search to see if this is a system board ROM
	# https://mcosre.sourceforge.net/docs/rom_v.html
	goto 6
	# TODO: This appears to be a fixed value, but what is it?
	set data [uint16]
	if {$data == 0x2A} {
		goto 0
		section "System ROM"
		sectioncollapse
		set checksum [uint32 -hex "Checksum"]
		set hex_checksum [format %x $checksum]
		move 4
		section "Version"
		set rom_ver [uint8 -hex "Major"]
		uint8 -hex "Minor"
		goto 76
		uint8 -hex "Sub"
		endsection
		# TODO: Currently we can only parse Universal ROMs -- unclear how this data was stored before
		if {$rom_ver >= 0x6} {
			goto 0x40
			uint32 "ROM Size"
			set filename "rom_maps/$hex_checksum"
			if { [file exists $filename] == 1 } {
				section "Symbols"
				sectioncollapse
				set map [open $filename "r"]
				set lines [split [read $map] "\n"]
				close $map
				foreach line $lines {
					# Skip empty lines
					if {$line == ""} {
						continue
					}
					set data [split $line " "]
					scan [lindex $data 1] %x raw_offset
					goto $raw_offset
					entry [lindex $data 0] [lindex $data 1] 1
				}
				endsection
			}
			goto 0x1A
			set rsrc_offset [uint32 "Resource Offset"]
			# Unlike DeclROM portions, this is an offset from the base
			goto $rsrc_offset
			set next [uint32 "First Entry Offset"]
			uint8 "Max Valid Index"
			set combo_size [uint8 "Combo Size?"]
			uint16 "Combo Version?"
			set header_size [uint16 "Header Size"]

			section "Resources"
			while {$next != 0} {
				goto $next
				section "Resource"
				sectioncollapse
				# TODO: Read it, don't just skip it
				move $combo_size
				set next [uint32 "Next Entry Offset"]
				set next_data [uint32 "Data Offset"]
				#goto $next_data
				set type [str 4 macroman "Type"]
				set id [uint16 "ID"]
				uint8 -hex "Attributes"
				set name_length [uint8 "Name Length"]
				if {$name_length > 0} {
					set name [str $name_length macroman "Name"]
					sectionname "$type \[$name\] ($id)"
				} else {
					sectionname "$type ($id)"
				}
				goto $next_data
				move [expr -$header_size]
				if {$header_size == 12} {
					uint32 -hex "More Attributes?"
				}
				set data_size [uint32 "Size"]
				uint32 "Fake pointer?"
				if {[expr $data_size-$header_size] > 0} {
					bytes [expr $data_size-$header_size] "Data"
				}
				# TODO: Add resource handlers
				if {$type == "CURS"} {
					goto $next_data
					bytes 32 "Cursor Data"
					bytes 32 "Cursor Mask"
					bytes 4 "Cursor Point"
				}
				endsection
			}
			endsection
		}
		endsection
	}

	# Because every offset after the directory is a uint, we know everything before it must be outside the DeclROM
	# TODO: That's not true? In practice it seems the other data is always after the directory, but it doesn't seem like it has to be
	goto 0
	if {$dir_start > 0} {
		bytes $dir_start "Non DeclROM Data"
	}

}
