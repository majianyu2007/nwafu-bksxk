/**
 * 初始化系统参数标题
 */
;
(function(_mode) {

    _mode.titleInit = function($dom) {
        titleInit($dom);
    };

    function titleInit($dom) {
        // 当前选课的学年，学期，周次
        //var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
        var xklc = JSON.parse(sessionStorage.getItem('currentBatch'));
        // 学年学期名称
        var schoolTermName = xklc.schoolTermName;
        // 周次范围
        var weekRange = xklc.weekRange;
        var html = schoolTermName + "&nbsp;" + weekRange;
        // 当前校区
        var currentCampus = JSON.parse(sessionStorage.getItem('currentCampus'));
        var teachingClassType = sessionStorage.getItem('teachingClassType');
        if (teachingClassType != 'QXKC' && currentCampus != null) {
        	html += '<span style="margin-left: 8px;">' + currentCampus.name + '<span>' +
					'<span class="home-change-campus" style="margin-left: 4px;color: #047ADC;cursor: pointer;">切换<span>';
        }
        $dom.html(html);
    }
})(window.CVTitleMode = window.CVTitleMode || {});

/**
 * 初始化退选课程列表
 */
;
(function(_public) {

    _public.init = function() {
        initTable();
    };

    function initTable() {
        var $dom = $('#cvDepartureCourse');
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var studentCode = studentInfo.code; // 学号
        var electiveBatch = studentInfo.electiveBatch;
        var electiveBatchCode = electiveBatch.code;
        var queryParam = {
            'studentCode': studentCode,
            'electiveBatchCode': electiveBatchCode
        };
        queryStudentReturnResults(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                var dataList = resp.dataList;
                if (dataList != null && dataList.length > 0) {
                    // 组合选课记录列表
                    var html = buildTableHtml(dataList);
                    $dom.html(html);
                } else {
                    // 没有选课记录
                    $dom.html('<h>你没有退课记录。</h>');
                }
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $dom.html('<h>查询退课日志失败，请稍后重试。</h>');
            }
        });
    }

    function buildTableHtml(dataList) {
        var html = '';
        var rowHtml = '';
        var data = null;
        for (var i = 0, length = dataList.length; i < length; i++) {
            data = dataList[i];
            var rowTemplate = $('#tpl-departurelog-list-row').html();
            // 处理空数据的展示
            var chooseVolunteer = data.chooseVolunteer;
            if (chooseVolunteer != null) {
                chooseVolunteer = '第' + chooseVolunteer + '志愿';
            } else {
                chooseVolunteer = '无';
            }
            var oeratePersonName = data.deleteOperatePersonName;
            if (oeratePersonName == null) {
                oeratePersonName = '-';
            }
            var teacherName = data.teacherName;
            var teacherNameAll = data.teacherName;
            if (teacherName == null) {
                teacherName = '-';
            }
            if(teacherNameAll == null){
            	teacherNameAll = '';
            }else{
            	teacherNameAll = 'title="' + teacherNameAll + '"';
            }
            var courseName = data.courseName;
            var sportName = data.sportName;
            if (sportName != null && sportName != '') {
                courseName += '(' + sportName + ')';
            }
            if (courseName == null) {
                courseName = '-';
            }
            var courseNatureName = data.courseNatureName;
            if (courseNatureName == null) {
                courseNatureName = '-';
            }
            var courseNameAll = courseName;

            var courseTypeName = data.courseTypeName;
            if (courseTypeName == null) {
                courseTypeName = '-';
            }

            rowHtml += rowTemplate.replace('@courseNumber', data.courseNumber)
                .replace('@courseNameAll', courseNameAll)
                .replace('@courseName', courseName)
                .replace('@teacherNameAll', teacherNameAll)
                .replace('@teacherName', teacherName)
                .replace('@courseTypeNameAll', courseTypeName)
                .replace('@courseTypeName', courseTypeName)  
                .replace('@courseNatureNameAll', courseNatureName)              
                .replace('@courseNatureName', courseNatureName)
                .replace('@deleteOperateTime', data.deleteOperateTime)
                .replace('@deleteOperatePersonName', oeratePersonName)
                .replace('@deleteOperateTypeName', data.deleteOperateTypeName)
                .replace('@grade', chooseVolunteer)
                .replace('@credit', data.credit)
                .replace('@hours', data.hours)
                .replace('@campusName', data.campusName)
                .replace('@delNumber', data.teachingClassID);
        }
        html = $('#tpl-departurelog-list').html().replace('@body', rowHtml);
        return html;
    }

})(window.CVDepartureCourse = window.CVDepartureCourse || {});

function initDeparturelog() {
	var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
    if(sysParam.kclbNotDisplay == '1'){
    	$('#cvDepartureCourse').addClass('no-kclb');
    }

    CVTitleMode.titleInit($('#sysParam'));
    CVDepartureCourse.init();
}