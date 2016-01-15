###*
 * TMS全局组件库开发构建工具
 * @author [Pang.J.G]
 * @version [0.0.1]
 * @date  [2016-01-15 15:58:53]
 * @required [gulp]
###

fs      = require 'fs'
path    = require 'path'
gulp    = require 'gulp'
_       = require 'lodash'
crypto  = require 'crypto'
yargs   = require 'yargs'
less    = require 'gulp-less'
uglify  = require 'uglify-js'
sprite  = require 'gulp-sprite-all'
autopre = require 'gulp-autoprefixer'
plumber = require 'gulp-plumber'
gutil   = require 'gulp-util'
log     = gutil.log
color   = gutil.colors
CleanCSS = require 'clean-css'
through2 = require 'through2'
imagemin = require 'imagemin-pngquant'
# 设置
_cfg = {}
try
    _cfg = require './config.json'
catch e
    log e

_root =  process.env.INIT_CWD
_srcPath = './'
_distPath = '../global/'


# 设置运行的命令参数
argv = yargs.option("e", {
        alias: 'env',
        demand: true
        default: _cfg.env or 'local',
        describe: color.cyan('项目的运行环境'),
        type: 'string'
    }).option("pre", {
        alias: 'prefix',
        default: _cfg.prefix or 'tms.',
        describe: color.cyan('设置生产文件名的前缀'),
        type: 'string'
    }).option("hash", {
        alias: 'hashlen',
        default: _cfg.hashLen or 10,
        describe: color.cyan('设置生产文件名的hash长度'),
        type: 'number'
    }).option("cdn", {
        alias: 'cdndomain',
        default: _cfg.cdnDomain or '',
        describe: color.cyan('设置项目发布的cdn域名'),
        type: 'string'
    })
    .help('h')
    .alias('h', 'help')
    .argv

# 设置项目的运行配置
_opt = 
    root: _root
    srcPath: _srcPath
    distPath: _distPath
    srcPaths: {}
    distPaths: {}
['less','js','img','font','html','sprite'].forEach (val)->
    _opt['srcPaths'][val] =  _srcPath + val
['css','img','js','font'].forEach (val)->
    _opt['distPaths'][val] = _distPath + val
opts = _.assign({},argv,_opt)
opts.env = argv.e
opts.env isnt 'www' && opts.comboDomain = "//#{opts.env}.#{opts.cdn}"
opts.mapPath = path.join(opts.distPath,'globalMap.json')
log(opts)

# 定义缓存
global.Cache = {}
global.Cache['cssMap'] = {}
global.Cache['jsMap'] = {}
global.Cache['imgMap'] = {}
global.Cache['fontMap'] = {}

# 一些正则
REGEX = 
    uri: /globalUri\(('|")([^'|^"]*)(\w+).(png|gif|jpg|html|js|css)('|")\)/g
    uriVal: /\([\s\S]*?\)/
    cssBg: /url\([\S\s]*?\)/g

###*
 * base functions
###
Tools = 
    # md5
    md5: (source) ->
        _buf = new Buffer(source)
        _str = _buf.toString("binary")
        return crypto.createHash('md5').update(_str, 'utf8').digest('hex')
    # make dir 
    mkdirsSync: (dirpath, mode)->
        if fs.existsSync(dirpath)
            return true
        else
            if Tools.mkdirsSync path.dirname(dirpath), mode
                fs.mkdirSync(dirpath, mode)
                return true
    # 错误警报
    errHandler:(e)->
        gutil.beep()
        gutil.beep()
        log e
    # 读取文件内容
    getFileSync: (file, encoding)->
        _encoding = encoding or 'utf8'
        fileCon = ''
        if fs.existsSync(file)
            stats = fs.statSync(file)
            if stats.isFile()
                fileCon = fs.readFileSync(file, _encoding)
        return fileCon
    # 读取json文件内容
    getJSONSync: (file) ->
        fileCon = Tools.getFileSync(file)
        data = {}
        if fileCon
            fileCon = fileCon.replace(/\/\/[^\n]*/g, '')
            try
                data = JSON.parse(fileCon)
            catch e
                console.log e
                
        return data

    # 压缩css/js源码
    minify: (source,type)->
        type = type or "js"
        if type == 'css'
            cssOpt = {
                    keepBreaks:false
                    compatibility:
                        properties:
                            iePrefixHack:true
                            ieSuffixHack:true
                }
            source = Tools._replaceCssBg(source)
            mangled = new CleanCSS(cssOpt).minify(source)
            return mangled.styles
        else
            source = Tools._replaceUriValue(source)
            mangled = uglify.minify(source,{fromString: true})
            return mangled.code
        
    # 压缩html
    htmlMinify: (source)->
        s = source
            .replace(/\/\*([\s\S]*?)\*\//g, '')
            .replace(/<!--([\s\S]*?)-->/g, '')
            .replace(/^\s+$/g, '')
            .replace(/\n/g, '')
            .replace(/\t/g, '')
            .replace(/\r/g, '')
            .replace(/\n\s+/g, ' ')
            .replace(/\s+/g, ' ')
            .replace(/>([\n\s]*?)</g,'><')
        return s

    # 判断是否window系统
    isWin: ->
        return process.platform is "win32"

    # 转换文件路径
    tranFilePath: (filePath)->
        _file = filePath or ""
        if Tools.isWin()
            _file = _file.replace /\\/g,'\/'
        return _file

    # 写入文件
    writeFile: (file, source,offlog)->
        # 文件存在并且MD5值一样，则不重复写入
        name = path.basename(file);
        if fs.existsSync(file) and Tools.md5(Tools.getFileSync(file)) is Tools.md5(source) 
            return false
        Tools.mkdirsSync(path.dirname(file))
        fs.writeFileSync(file, source, 'utf8')
        offlog or log("'" + color.cyan(path.basename(file)) + "'", "build success.")

    # 生成 debug 文件路径
    _setDegbugPath: (parse)->
        parse.base = "debug." + parse.name + parse.ext
        return path.format(parse)
    # 生成 dist 文件路径
    _setDistPath: (parse,hash)->
        parse.base = opts.prefix + parse.name + "." + hash.substring(0,opts.hashLen) + parse.ext
        return path.format(parse)

    # 生成带有标志前缀的文件路径
    _setSrcPath: (parse)->
        parse.base = opts.prefix + parse.name + parse.ext
        return path.format(parse)

    # 生成缓存的类型
    _setCacheType: (parse)->
        return parse.ext.replace('.','')

    # 从缓存中读取 dist 文件路径
    _getDistName: (type,name)->
        if _.has(global.Cache,type + "Map") and global.Cache[type + "Map"][name]
            return global.Cache[type + "Map"][name].distPath
        else
            return name
    # 替换JS中的内嵌资源
    # 例如：globalUri("dir/name.ext")-->globalUri("dir/name.md5hash.ext")
    _replaceUriValue: (source)->
        return source.replace REGEX.uri,(res)->
            _val = res.match(REGEX.uriVal).shift().replace(/[\(\)"']/g,'')
            _valArr = _val.split('/')
            type = _valArr.shift()
            name = _valArr.join('/')
            distName = Tools._getDistName(type,name)
            return res.replace(name,distName)
    # 替换css中的背景图片或字体文件引用资源
    # 例如：url('xxxxx.xxx')-->url('xxxxx.md5hash.xxx')
    _replaceCssBg: (source)->
        return source.replace REGEX.cssBg,(res)->
            _val = res.match(REGEX.uriVal).shift().replace(/[\(\)"']/g,'')
            if _val.indexOf('font/') != -1
                name = _val.split('font/')[1]
                            .split(/(\?|#)/)[0]
                distName = Tools._getDistName('font',name)
                return res.replace(name,distName)
            else if _val.indexOf('img/') != -1
                name = _val.split('img/')[1]
                distName = Tools._getDistName('img',name)
                return res.replace(name,distName)
            else
                return res
    # 处理img的pipe管道对象
    throughImg: (type)->
        _type = type or 'img'
        return through2.obj (file, enc, callback)->
            if file.isNull()
                return callback(null, file)
            else if file.isStream()
                throw new Error('Streams are not supported!')
            relative = file.relative
            _contents = file.contents
            _parse = path.parse(relative)
            _hash = Tools.md5(_contents.toString())
            _distPath = Tools._setDistPath(_parse,_hash).replace(opts.prefix,'')

            # 生成压缩文件
            opts.env isnt 'local' and Tools.writeFile(path.join(opts.distPaths[_type],_distPath),_contents,1)

            # 缓存
            global.Cache[_type + "Map"][relative] = 
                hash: _hash
                distPath: _distPath
                # source: _contents
            return callback(null,file)

    # 处理css和js的pipe管道对象
    throughObj: ->
        return through2.obj (file, enc, callback)->
            if file.isNull()
                return callback(null, file)
            else if file.isStream()
                throw new Error('Streams are not supported!')
            relative = file.relative
            _parse = path.parse(relative)
            _type = Tools._setCacheType(_parse)
            _contents = file.contents
            # 压缩处理
            _minContents = Tools.minify(_contents.toString(),_type)
            _hash = Tools.md5(_minContents)
            _srcPath = Tools._setSrcPath(_parse)
            _distPath = Tools._setDistPath(_parse,_hash)

            # 生成压缩文件
            Tools.writeFile(path.join(opts.distPaths[_type],_srcPath),_minContents)
            opts.env isnt 'local' and Tools.writeFile(path.join(opts.distPaths[_type],_distPath),_minContents)

            # 生成Debug对象
            _debugPath = Tools._setDegbugPath(_parse)
            file.path = path.join(opts.distPaths[_type],_debugPath)

            # 缓存
            global.Cache[_type + "Map"][relative] = 
                hash: _hash
                distPath: _distPath
                # source: _contents

            return callback(null,file)

    # watch状态下对文件变化的提示
    tips: (res)->
        log "'" + color.cyan(path.basename(res.path)) + "'",color.yellow(res.type) + "."

# 主构建函数
build = 
    # 初始化
    init: ->
        log('初始化 global 资源目录')
        _makePath = (dir)->
            Tools.mkdirsSync(dir)
            log("'" + color.cyan("#{dir}") + "'","dir made success!")
        # src paths
        for val,key of opts.srcPaths
            _dir = opts.srcPath + val
            _makePath(_dir)
        # dist paths
        _makePath(opts.distPath)
        for val,key of opts.distPaths
            _dir = opts.distPath + val
            _makePath(_dir)

    # 雪碧图
    sprite: (cb)->
        _cb = cb or ->
        spOpts = 
            srcPath: opts.srcPaths.sprite
            lessOutPath: path.join opts.srcPaths.less,'_sprite'
            imgOutPath: path.join opts.srcPaths.img,'sprite'
        spCtrl = new sprite.init(spOpts)
        spCtrl.output ->_cb()
    # 处理图片
    font: (files,cb)->
        _cb = cb or ->
        gulp.src(files)
            .pipe plumber({errorHandler: Tools.errHandler})
            .pipe Tools.throughImg('font')
            .pipe gulp.dest(opts.distPaths.font)
            .on 'end', ->
                _cb()
    # 处理图片
    img: (files,cb)->
        _cb = cb or ->
        gulp.src(files)
            .pipe plumber({errorHandler: Tools.errHandler})
            .pipe imagemin({quality: '65-80', speed: 4})()
            .pipe Tools.throughImg()
            .pipe gulp.dest(opts.distPaths.img)
            .on 'end', ->
                _cb()
    # less构建
    css: (files,cb)->
        _cb = cb or ->
        _lessPath = opts.srcPaths.less
        _cssPath = opts.distPaths.css
        gulp.src(files)
            .pipe plumber({errorHandler: Tools.errHandler})
            .pipe less
                compress: false
                paths: [_lessPath]
            .pipe autopre()
            .pipe Tools.throughObj()
            .pipe gulp.dest(_cssPath)
            .on 'end', ->
                _cb()

    # js构建
    js: (files,cb)->
        _cb = cb or ->
        _jsOutPath = opts.distPaths.js
        gulp.src(files)
            .pipe plumber({errorHandler: Tools.errHandler})
            .pipe Tools.throughObj()
            .pipe gulp.dest(_jsOutPath)
            .on 'end',_cb
    # 读取map
    getMap: ->
        map = Tools.getJSONSync(opts.mapPath)
        global.Cache = _.assign(global.Cache,map)

    # 保存map
    saveMap: ->
        Tools.writeFile(opts.mapPath,JSON.stringify(global.Cache,null,4))
        

# gulp任务
fontFiles = [
        path.join(opts.srcPaths.font, '*.{eot,woff,svg,ttf,otf}')
    ]
imgFiles = [
        path.join(opts.srcPaths.img, '*.{png,jpg,gif,ico}')
        path.join(opts.srcPaths.img, '**/*.{png,jpg,gif,ico}')
    ]
lessFiles = [
        path.join(opts.srcPaths.less, '*.less')
        path.join(opts.srcPaths.less, '**/*.less')
        "!#{path.join(opts.srcPaths.less, '_*.less')}"
        "!#{path.join(opts.srcPaths.less, '_**/*.less')}"
        "!#{path.join(opts.srcPaths.less, '_**/**/*.less')}"
        "!#{path.join(opts.srcPaths.less, '_**/**/**/*.less')}"
    ]
jsFiles = [
        path.join(opts.srcPaths.js, '*.js')
        path.join(opts.srcPaths.js, '**/*.js')
    ]
gulp.task 'init',->
    build.init()

gulp.task 'getmap',->
    build.getMap()

gulp.task 'sprite',['getmap'],->
    build.sprite()

gulp.task 'font',['sprite'],->
    build.font(fontFiles)

gulp.task 'img',['font'],->
    build.img(imgFiles)

gulp.task 'css',['img'],->
    build.css(lessFiles)

gulp.task 'js',['css'],->
    build.js jsFiles,->
        build.saveMap()

gulp.task "watch",->
    _.isEmpty(global.Cache['cssMap']) and build.getMap()
    gulp.watch lessFiles.slice(0,2),(res)->
        Tools.tips(res)
        res.type isnt 'deleted' and build.css lessFiles, ->
            build.saveMap()
    gulp.watch jsFiles,(res)->
        Tools.tips(res)
        res.type isnt 'deleted' and build.js res.path,->
            build.saveMap()
    gulp.watch imgFiles,(res)->
        Tools.tips(res)
        res.type isnt 'deleted' and build.img res.path,->
            build.saveMap()
    gulp.watch fontFiles,(res)->
        Tools.tips(res)
        res.type isnt 'deleted' and build.font(res.path)
    gulp.watch opts.srcPaths.sprite + "**/*.png",(res)->
        Tools.tips(res)
        build.sprite()

gulp.task 'default',['js'],->
    return false if opts.env isnt 'local'
    gulp.start('watch')
    # log(global.Cache)
    