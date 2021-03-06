
# ObjectBuilder class definition
# Accepts parametes from the FormModel
class ObjectBuilder

  # pathsToShapes
  # Tranforms the SVG paths into shapes consumable by THREE.js
  pathsToShapes: (paths) ->

    # Stores transformed shapes
    shapes = []

    # Iterates over each path...
    for each in paths

      # Turn each SVG path into a three.js shape
      path = d3.transformSVGPath(each)

      # We may have had the winding order backward.
      # NOTE - the Path.prototype.toShapes method is not defined in Three.js v0.84
      newShapes = path.toShapes(false)

      # Add these three.js shapes to an array.
      shapes = shapes.concat(newShapes)

    return shapes

  # getExtruded
  # Extrudes the SVG using shapes and options
  getExtruded: (shapes, options) ->

    # Extrude all the shapes WITHOUT Bevel
    extruded = new THREE.ExtrudeGeometry(shapes, { amount: options.height, bevelEnabled: false })

    # Find the bounding box of this extrusion with no bevel
    # there's probably a smarter way to get a bounding box without extruding...
    extruded.computeBoundingBox()
    maxBbExtent = @getMaxExtent(extruded.boundingBox)

    # Extrude with bevel instead if requested.
    if options.bevel

      extrudeOptions =
        amount:         0
        bevelEnabled:   true
        bevelThickness: options.height
        bevelSize:      options.height * maxBbExtent / options.width
        bevelSegments:  1

      extruded = new THREE.ExtrudeGeometry(shapes, extrudeOptions)

    # Use negative scaling to invert the image
    # Why do we have to flip the image to keep original SVG orientation?
    if !options.invert
      invertTransform = new THREE.Matrix4().makeScale(-1, 1, 1)
      extruded.applyMatrix(invertTransform)

    # Into a mesh of triangles
    mesh = new THREE.Mesh(extruded, options.material)

    # Scale to requested size (lock aspect ratio)
    scaleTransform = new THREE.Matrix4().makeScale(options.width / maxBbExtent, options.width / maxBbExtent, 1)

    # Keep the depth as-is
    mesh.geometry.applyMatrix(scaleTransform)

    # Returns extruded geometry
    return mesh

  # svgToThree
  extrudeSVG: (paths, options) ->

    # Bevel?
    # options.bevel = if options.height < 0 or !options.platform.enabled then false else options.bevel

    # Gets shapes from paths
    shapes = @pathsToShapes(paths)

    # Negative typeDepths are ok, but can't be deeper than the base
    # if options.platform.enabled and options.height < 0 and Math.abs(options.height) > options.platform.height
    #   options.height = -1 * options.platform.height

    # Extrudes shapes into mesh geometry
    mesh = @getExtruded(shapes, options)

    # Center on X/Y origin
    mesh.geometry.computeBoundingBox()
    boundBox = mesh.geometry.boundingBox
    translateTransform = new THREE.Matrix4().makeTranslation(-(Math.abs((boundBox.max.x - (boundBox.min.x)) / 2) + boundBox.min.x), -(Math.abs((boundBox.max.y - (boundBox.min.y)) / 2) + boundBox.min.y), 0)
    mesh.geometry.applyMatrix(translateTransform)

    # Rotate 180 deg
    # Why is this required? Different coordinate systems for SVG and three.js?
    rotateTransform = new THREE.Matrix4().makeRotationZ(Math.PI)
    mesh.geometry.applyMatrix rotateTransform

    # So that these attributes of the mesh are populated for later
    mesh.geometry.computeBoundingBox()
    mesh.geometry.computeBoundingSphere()

    return mesh

  # # # # # # # # # #

  # Determine the finished size of the extruded SVG with potential bevel
  getMaxExtent: (bounds) ->
    svgWidth    = bounds.max.x - (bounds.min.x)
    svgHeight   = bounds.max.y - (bounds.min.y)
    maxBbExtent = if svgWidth > svgHeight then svgWidth else svgHeight
    return maxBbExtent

  getRectangularPlatform: (mesh, opts) ->

    # Get max extent
    maxBbExtent = @getMaxExtent(mesh.geometry.boundingBox)

    # Now make the rectangular base plate
    boxSize = maxBbExtent + Number(opts.platform.buffer)
    platformGeometry = new THREE.BoxGeometry(boxSize, boxSize, opts.platform.height)
    platformMesh = new THREE.Mesh(platformGeometry, opts.material)
    return platformMesh

  # # # # #

  getCircularPlatform: (mesh, opts) ->

    # Find SVG bounding radius
    svgBoundRadius = mesh.geometry.boundingSphere.radius

    # Cylinder parameters
    radius            = svgBoundRadius + Number(opts.platform.buffer)
    radiusSegments    = 60
    platformGeometry  = new THREE.CylinderGeometry(radius, radius, opts.platform.height, radiusSegments)

    # Number of faces around the cylinder
    platformMesh = new THREE.Mesh(platformGeometry, opts.material)
    rotateTransform = new THREE.Matrix4().makeRotationX(Math.PI / 2)
    platformMesh.geometry.applyMatrix(rotateTransform)

    # Returns platform mesh
    return platformMesh

  # # # # #

  getPlatformObject: (mesh, opts) ->
    # Rectangular platform
    if opts.platform.shape == 'rect'
      platformMesh = @getRectangularPlatform(mesh, opts)

    # Circular platform
    else
      platformMesh = @getCircularPlatform(mesh, opts)

    # By default, base is straddling Z-axis, put it flat on the print surface.
    translateTransform = new THREE.Matrix4().makeTranslation(0, 0, opts.platform.height/2 )
    platformMesh.geometry.applyMatrix(translateTransform)
    return platformMesh

  # # # # #

  # Platform Helper
  setPlatform: (mesh, opts) ->
    return mesh unless opts.platform.enabled

    # Offset mesh to accomodate platform height
    # Shift the SVG portion away from the bed to account for the base
    translateTransform = new THREE.Matrix4().makeTranslation(0, 0, opts.platform.height)
    mesh.geometry.applyMatrix(translateTransform)

    # # # # #

    # Gets platform object
    platform_mesh = @getPlatformObject(mesh, opts)

    # For constructive solid geometry (CSG) actions
    baseCSG = new ThreeBSP(platform_mesh)
    svgCSG = new ThreeBSP(mesh)

    # # If we haven't inverted the type, the SVG is "inside-out"
    if !opts.invert
      svgCSG = new ThreeBSP(svgCSG.tree.clone().invert())

    # Positive typeDepth means raised
    # Negative typeDepth means sunken
    # TODO - should be range slider from (-x - x)
    if opts.height > 0
      finalObj = baseCSG.union(svgCSG).toMesh(opts.material)
    else
      finalObj = baseCSG.intersect(svgCSG).toMesh(opts.material)

    # Merges mesh and platform
    return finalObj

  # Edges helper
  setEdges: (mesh, opts) ->
    return false unless opts.edges.enabled
    edges = new THREE.EdgesHelper(mesh, opts.edges.color)
    @objects.push(edges)
    return

  # Render object in scene
  build: (paths, options) ->

    # Set height to -1 if it doesnt exist, or equals 0
    if options.height == 0 || options.height == undefined
      options.height = 1

    # Color
    options.color = new THREE.Color(options.color)

    # Material (derived from color)
    options.material = new THREE.MeshLambertMaterial({
      color:    options.color
      emissive: options.color
      side:     THREE.DoubleSide
    })

    # Create an extrusion from the SVG path shapes
    svgMesh = @extrudeSVG(paths, options)

    # Creates a platform and attaches to svgMesh, if platform.enabled
    svgMesh = @setPlatform(svgMesh, options)

    # Array of objects returned by this method
    # Each object will be rendered in the THREE scene
    @objects = []

    # Add the final geometry to the scene
    @objects.push(svgMesh)

    # Edges
    @setEdges(svgMesh, options)

    return @objects

# # # # #

module.exports = ObjectBuilder
