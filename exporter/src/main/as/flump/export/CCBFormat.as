package flump.export
{
	import com.threerings.util.F;
	
	import flash.filesystem.File;
	import flash.geom.Rectangle;
	import flash.utils.Dictionary;
	import flash.utils.IDataOutput;
	
	import flump.mold.AtlasTextureMold;
	import flump.mold.KeyframeMold;
	import flump.mold.LayerMold;
	import flump.mold.MovieMold;
	import flump.xfl.XflLibrary;
	
	public class CCBFormat extends PublishFormat
	{

		public static const NAME :String = "CCB";
		public static const FILE_PREFIX:String = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n';
		public static const RESOURCE_DIR:String = "ccbResources";
		
		protected var _destinationDir: File;
		protected var _resourceDir: File;
		protected var _textureHash:Dictionary = new Dictionary();
		
		public function CCBFormat( destDir :File, lib :XflLibrary, conf :ExportConf) {
			super(destDir, lib, conf);
			_destinationDir = _destDir.resolvePath( conf.name + "/" + NAME + "/" + lib.location + "/" );
			_resourceDir = _destinationDir.resolvePath( RESOURCE_DIR + "/" );
		}
		
		override public function get modified () :Boolean {
			var md5File:File = _destinationDir.resolvePath("md5");
			return !md5File.exists || Files.read(md5File).toString() != _lib.md5;
		}
		
		override public function publish () :void {
			
			// Ensure any previously generated atlases don't linger
			if (_destinationDir.exists) _destinationDir.deleteDirectory(true); // deleteDirectoryContents=
			_destinationDir.createDirectory();
			
			// --- Create resources -------------------------------------------
			var atlasCount:int = 0, pListFileName:String;

			for each (var atlas:Atlas in createAtlases("")) {

				var atlasBound:Rectangle = atlas.toBitmap().rect;
				var frames:Object = {};
				
				var assetData:Object={
					frames: frames,
					metadata: {
						format: 2,
						textureFileName: atlas.filename,
						realTextureFileName: atlas.filename,
						size: "{"+ atlasBound.width +","+ atlasBound.height +"}",
						smartupdate: ""
					}
				};

				pListFileName = "atlas" + atlasCount + ".plist";

				for each( var texture:AtlasTextureMold in atlas.toMold().textures ){
					_textureHash[ texture.symbol ] = {
						texture: texture,
						pListFile: pListFileName
					};
					var frame:String = "{{"+ texture.bounds.left + "," + texture.bounds.top + "},{" + texture.bounds.width + "," + texture.bounds.height +"}}";
					frames[ texture.symbol ] = {
						rotated: false,
						frame: frame, sourceColorRect: frame,
						// Source : The png from which the texture was created ( Not the final stitched atlas png ) : Not sure about use of following properties
						offset: "{0,0}", // Source depended : { -(source.width-texture.width)/2, (source.width-texture.width)/2 } 
						sourceSize: "{"+ atlasBound.width +","+ atlasBound.height +"}" // Source depended : Size of source png
					};
				}
				
				Files.write( _resourceDir.resolvePath( atlas.filename ), F.partial(AtlasUtil.writePNG, atlas, F._1));
				writeAsPlist( _resourceDir.resolvePath( pListFileName ), assetData );

				atlasCount++;
			}
			
			for each( var movie:MovieMold in _lib.publishedMovies ){
				writeAsPlist( _destinationDir.resolvePath( movie.id+"-movie.ccb" ), xflToCCBObj(movie) );
			}
			
			Files.write( _destinationDir.resolvePath("md5") , function (out :IDataOutput):void { out.writeUTFBytes( _lib.md5 ); });
		}
		
		private function writeAsPlist( file:File, data:Object ):void{
			var xml:XML = <plist version="1.0">{ objectToPList(data) }</plist>;
			Files.write( file , function (out :IDataOutput):void { out.writeUTFBytes(FILE_PREFIX+xml.toString()); });
		}
		
		private function objectToPList( data:Object ):XML{
			var xml:XML;
			
			switch( typeof data ){
				case "string": xml = <string>{data}</string>; break;
				case "boolean": xml = data ? <true/>:<false/>; break;
				case "number":
					if( data is int ) xml = <integer>{data}</integer>;
					else xml = <real>{data}</real>;
					break;
				case "object":
					if( data is Array ){
						xml = <array></array>;
						for each( var arrItem:Object in data ){
							xml.appendChild( objectToPList(arrItem) );
						}
					}
/*					else if( data is Date ){ //Wont be required in CCB files
						var date:Date = data as Date;
						xml = <date>{ISO8601Util.formatBasicDateTime(date)}</date>; break;
					}
					else if( data is ByteArray ){
						var base64:Base64Encoder = new Base64Encoder();
						base64.encodeBytes( ByteArray(data) );
						xml = <data>{base64.toString()}</data>;
					}
*/					else{
						xml = <dict></dict>;
						for( var key:String in data ){
							xml.appendChild( <key>{key}</key> );
							xml.appendChild( objectToPList( data[key] ) );
						}
					}
					break;
				default:
					throw( new Error(" Error in converting to PList : Unsupported type") );
					break;
			}
			
			return xml;
		}
		
		private function getCCBNode( name:String, children:Object=null ):Object{
			
			var texture:AtlasTextureMold = _textureHash[name].texture;
			
			var node:Object = {
				baseClass: "CCSprite",
				customClass: "",
				displayName: name,
				seqExpanded: true,
				memberVarAssignmentName: "",
				memberVarAssignmentType: 0,
				properties: [
					{ name: "position", type: "Position", value: [ 0, 0, 0 ] },
					{ name: "ignoreAnchorPointForPosition", type: "Check", value: false },
					{
						name: "anchorPoint",
						type: "Point",
						value: [ texture.origin.x/texture.bounds.width, 1-texture.origin.y/texture.bounds.height ] //Pixel to UV
					},
					{
						name: "scale",
						type: "ScaleLock",
						value: [ 1, 1, false, 0 ]
					},
					{
						name: "displayFrame",
						type: "SpriteFrame",
						value: [ RESOURCE_DIR + "/" + _textureHash[name].pListFile + ".plist", name]
					}
				]
			};
			
			if( children ) node.children = children;
			
			return node;
			
		}
		
		private function addPropertyKeyFrame( propObj:Object, name:String, type:int, time:Number, value:*, easing:Object ):void{

			propObj[name] ||= {
				name: name,
				type: type,
				keyframes:[]
			};
			propObj[name].keyframes.push({
				name: name,
				time: time,
				type: type,
				value: value,
				easing: easing
			});
			
		}
		
		private function addAnimProp( animPropObj:Object, previousKF:KeyframeMold, currentKF:KeyframeMold, totalFrames:int ):void{
			
			var time:Number = Number(totalFrames)/_lib.frameRate;
			var easing:Object;
			
			if( !currentKF.tweened ) easing = { type:0 }; // Instant - TODO : Test
			else if( currentKF.ease>0 ) easing = { opt:Math.abs( currentKF.ease ) , type:2 }; // CubicIn
			else if( currentKF.ease<0 ) easing = { opt:Math.abs( currentKF.ease ) , type:3 }; // CubicOut
			else easing = { type:1 }; // Linear

			if( previousKF ){
				if( previousKF.visible != currentKF.visible )
					addPropertyKeyFrame( animPropObj, "visible", 1, time, true, easing ); // Each entry toggles visibility
				if( previousKF.skewX != currentKF.skewX )
					addPropertyKeyFrame( animPropObj, "rotation", 2, time, currentKF.skewX, easing );
				if( previousKF.x != currentKF.x || previousKF.y != currentKF.y )
					addPropertyKeyFrame( animPropObj, "position", 3, time, [ currentKF.x, -currentKF.y ], easing );
				if( previousKF.scaleX != currentKF.scaleX || previousKF.scaleY != currentKF.scaleY )
					addPropertyKeyFrame( animPropObj, "scale"   , 4, time, [ currentKF.scaleX, currentKF.scaleY ], easing );
				if( previousKF.alpha != currentKF.alpha )
					addPropertyKeyFrame( animPropObj, "opacity" , 5, time, Math.round( currentKF.alpha*255 ), easing );
				if( previousKF.ref != currentKF.ref )
					addPropertyKeyFrame( animPropObj, "displayFrame", 7, time, [ currentKF.ref, RESOURCE_DIR + "/" + _textureHash[currentKF.ref].pListFile ], easing );
			}
			else{
				addPropertyKeyFrame( animPropObj, "visible", 1, time, true, easing );
				addPropertyKeyFrame( animPropObj, "rotation", 2, time, currentKF.skewX, easing );
				addPropertyKeyFrame( animPropObj, "position", 3, time, [ currentKF.x, -currentKF.y ], easing );
				addPropertyKeyFrame( animPropObj, "scale"   , 4, time, [ currentKF.scaleX, currentKF.scaleY ], easing );
				addPropertyKeyFrame( animPropObj, "opacity" , 5, time, Math.round( currentKF.alpha*255 ), easing );
//				addPropertyKeyFrame( animPropObj, "color", 6, time, [ R, G, B ], easing );
				addPropertyKeyFrame( animPropObj, "displayFrame", 7, time, [ currentKF.ref, RESOURCE_DIR + "/" + _textureHash[currentKF.ref].pListFile ], easing );
			}
			
		}

		private function xflToCCBObj( movie:MovieMold ):Object{
			
			var animElements:Array = [];
			var elementNode:Object, animProps:Object, currentFrames:int, previousKF:KeyframeMold=null, maxLength:int=0;

			for each (var layer:LayerMold in movie.layers){
				elementNode = getCCBNode( layer.keyframes[0].ref );
				animProps = {};
				elementNode.animatedProperties = {0:animProps};
					
				currentFrames = 0;
				for each (var kf:KeyframeMold in layer.keyframes){
					addAnimProp( animProps, previousKF, kf, currentFrames );
					currentFrames += kf.duration;
					previousKF = kf;
				}
				
				if( maxLength<currentFrames ) maxLength=currentFrames;
					
				animElements.push( elementNode );
			}

			var nodeGraph:Object = {
				baseClass: "CCLayer",
				customClass: "",
				displayName: "CCLayer",
				memberVarAssignmentName: "",
				memberVarAssignmentType: 0,
				properties:[
					{ name: "contentSize", type: "Size", value: [ Number(100), Number(100), 1 ] }, // In percent
					{ name: "anchorPoint", type: "Point", value: [ 0.5, 0.5 ] },
					{ name: "scale", type: "ScaleLock", value: [ 1.0, 1.0, false, 0 ] },
					{ name: "ignoreAnchorPointForPosition", type: "Check", value: true }
				],
				children: animElements
			};
			
			var ccbObj:Object = {
				centeredOrigin: false,
				currentResolution: 0,
				currentSequenceId: 0,
				fileType: "CocosBuilder",
				fileVersion: 4,
				guides: [],
				notes: [],
				stageBorder: 0,
				nodeGraph: nodeGraph,
				resolutions: [{ name: "iPad Landscape", centeredOrigin: false, ext: "ipad iphonehd", height: 768, width: 1024, scale: 2.0}],
				sequences: [
					{ 	autoPlay: true,
						sequenceId: 0, chainedSequenceId: -1,
						name: "Default Timeline", offset: 0.0, position: 0, scale: 128.0, // CCBuilder specific
						length: Number( maxLength )/_lib.frameRate,
						resolution: _lib.frameRate
					}
				]
			};
						
			return ccbObj;
		}

	}
}