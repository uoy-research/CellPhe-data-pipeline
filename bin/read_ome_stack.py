import imagej
import scyjava as sj

ij = imagej.init(["net.imagej:imagej", "sc.fiji:TrackMate:7.13.2", "ome:bio-formats_plugins:8.0.1"], add_legacy=False)
BF = sj.jimport('loci.plugins.BF')
options = sj.jimport('loci.plugins.in.ImporterOptions')() # import and initialize ImporterOptions
options.setOpenAllSeries(True)  # What does this do?
options.setVirtual(True)  # Deff want this?
options.setId("/path/to/file.tiff")  # Can't open just companion file can we?
imps = BF.openImagePlus(options)
