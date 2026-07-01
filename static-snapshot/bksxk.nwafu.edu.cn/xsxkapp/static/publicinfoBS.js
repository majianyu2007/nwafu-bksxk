function queryNoticeList(param) {
	var timestamp = new Date().getTime();
	return BH_UTILS.doAjax(
        BaseUrl + '/sys/xsxkapp/publicinfo/notice.do?timestamp=' + timestamp,
        param,
        'GET',
        {}
    );
}

function queryProblemList() {
	var timestamp = new Date().getTime();
	return BH_UTILS.doAjax(
        BaseUrl + '/sys/xsxkapp/publicinfo/problem.do?timestamp=' + timestamp,
        {},
        'GET',
        {}
    );
}