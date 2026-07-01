/**
 * 查询课程信息
 */
function queryJsInfo(JSH) {
    /*var timestamp = new Date().getTime();*/
    return BH_UTILS.doAjax(
	    BaseUrl + "/sys/xsxkapp/publicinfo/queryjzg.do?jsh=" + JSH, {},
	    "get"
	);
}

/*查询页脚信息*/
function queryCelebrityFamous() {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/celebrityfamous.do?timestamp=" + timestamp,
        {},
        "get"
    );
}
