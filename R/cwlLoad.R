.loadCWL <- function(rscript, env = .GlobalEnv, return = FALSE){
    .env <- new.env()
    source(rscript, .env)
    objs <- ls(.env)
    oidx <- sapply(objs,
                   function(x)is(get(x, envir = .env), "cwlProcess"))
    if(sum(oidx)==1){
        idx <- oidx
    }else if(sum(oidx)>1){
        oclass <- sapply(objs,
                         function(x)class(get(x, envir = .env)))
        idx <- oclass == "cwlWorkflow"
        if(sum(idx)==0) idx <- tail(which(oidx), 1)
        oidx <- oidx & !idx

        for(i in seq(sum(oidx))){
            assign(objs[oidx][i],
                   get(objs[oidx][i], envir = .env),
                   envir = env)
            message(objs[oidx][i], " loaded")
        }
    }
    if(return){
        get(objs[idx], envir = .env)
    }else{
        assign(objs[idx],
               get(objs[idx], envir = .env),
               envir = env)
        message(objs[idx], " loaded")
    }
}

.loadCWLURL <- function(url){
    cwlpath <- paste0(tempfile(), ".cwl")
    download.file(url, cwlpath)
    readCWL(cwlpath)
}

#' @importFrom git2r clone
.loadCWLgit <- function(repo, cwlfile, dir = tempdir(), ...){
    github_repo <- paste0("https://github.com/", repo)
    localdir <- file.path(dir, basename(github_repo))
    clone(github_repo, local_path = localdir, ...)

    cfile <- file.path(localdir, cwlfile)
    stopifnot(file.exists(cfile))
    readCWL(cfile)
}

#' cwlLoad
#' 
#' To source Rcwl scripts
#' @param rname The name or filepath of tool or pipeline to install
#'     (`rname` or `fpath` column from the `bfc` object returned from
#'     `cwlSearch`). It can also be a CWL url or a github repo.
#' @param bfc The `BiocFileCache` object for the recipes. The default
#'     is NULL which automatically detect the "Rcwl" cache directory.
#' @param env The R enviroment to export to. The default is
#'     `.GlobalEnv`.
#' @param cwlfile For github repo input, The relative path of a CWL
#'     file inside of the github repo.
#' @param dir For github repo input, the directory to clone the repo.
#' @param ... More options from git2r::clone.
#' @return A `cwlProcess` object. For pipelines, the dependent tools
#'     will also loaded.
#' @details Note to developers that the dependent Rcwl scripts should
#'     be included in the recipe with `@include` tag.
#' @import methods
#' @export
#' @examples
#' \dontrun{
#' tls <- cwlSearch("bwa")
#' title(tls)
#' bwa <- cwlLoad("tl_bwa")
#' bwa <- cwlLoad(tls$fpath[tls$rname == "tl_bwa"])  ## equivalent
#' bwa
#' }
cwlLoad <- function(rname, bfc = NULL, env = .GlobalEnv,
                    cwlfile = NULL, dir = tempdir(), ...) {
    if(grepl("http", rname) & grepl("\\.cwl$", rname)){
        .loadCWLURL(rname)
    }else if(!file.exists(rname) && grepl("\\/", rname)){
        .loadCWLgit(rname, cwlfile = cwlfile, dir = dir, ...)
    }else{
        bfcpath <- Sys.getenv("cachePath")
        if(bfcpath != ""){
            cachePath <- file.path(bfcpath, "Rcwl")
            bfc <- BiocFileCache(cachePath, ask = FALSE)
        }else if(is.null(bfc)){
            cachePath <- user_cache_dir("Rcwl")
            bfc <- BiocFileCache(cachePath, ask = FALSE)
        }
        if (missing(rname))
            stop("Please provide a valid name or filepath for the tool/pipeline.")
        idx <- match(rname, bfcinfo(bfc)$rname)
        if (!is.na(idx)) {
            fpath <- bfcrpath(bfc)[idx]
        } else {
            if (file.exists(rname)){
                fpath <- rname
            } else {
                stop("Please provide a valid name or filepath for the tool/pipeline.")
            }
        }

        scripts <- readLines(fpath)
        iscripts <- grep("@include", scripts, value = TRUE)
        if(length(iscripts) > 0){
            rscripts <- grep(".R$",
                             unlist(strsplit(iscripts, split = " ")),
                             value = TRUE)
            if(length(rscripts) > 0){
                sapply(rscripts, function(x){
                    rscript <- file.path(dirname(fpath), x)
                    if(any(grepl("cwlWorkflow", readLines(rscript)))){
                        cwlInstall(rscript, bfc = bfc, env = env)
                    }else{
                        .loadCWL(rscript, env)
                    }
                })
            }
        }
        .loadCWL(fpath, env, return = TRUE)        
    }
}
